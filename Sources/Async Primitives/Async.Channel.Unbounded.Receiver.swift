// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

// Async channels require task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

internal import Container_Primitives

extension Async.Channel.Unbounded {
    /// A receiver for an unbounded channel.
    ///
    /// `Receiver` is `~Copyable` (unique) and transferable across tasks.
    /// Exactly one receiver exists per channel, enforcing single-receiver
    /// semantics at the type level.
    ///
    /// The single-suspended-receiver invariant (at most one task may be
    /// suspended in `receive()` at a time) is enforced via runtime precondition.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Unbounded()
    ///
    /// // Receive elements (may suspend if buffer empty)
    /// while let value = try await channel.receiver.receive() {
    ///     process(value)
    /// }
    ///
    /// // Or iterate via AsyncSequence view
    /// for try await value in channel.receiver.elements {
    ///     process(value)
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// `Receiver` is `@unchecked Sendable` - it may be moved to another task
    /// for the canonical "handoff to consumer task" pattern. The mutex guards
    /// all state access. Concurrent suspension is caught by precondition.
    public struct Receiver: ~Copyable, @unchecked Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }
    }
}

// MARK: - Receive Operations

extension Async.Channel.Unbounded.Receiver {
    /// Receive the next element from the channel.
    ///
    /// Suspends if the buffer is empty until an element becomes available
    /// or the channel is closed and drained.
    ///
    /// - Returns: The next element, or `nil` if the channel is closed and drained.
    /// - Throws: `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
    @inlinable
    public func receive() async throws(Async.Channel<Element>.Error) -> Element? {
        // Fast path: try immediate receive
        let fastAction = storage.withLock { state in
            state.receive.take()
        }

        switch fastAction {
        case .val(let element):
            return element
        case .end:
            return nil
        case .wait:
            break // Fall through to slow path
        }

        // Check cancellation before entering slow path
        if Task.isCancelled {
            throw .cancelled
        }

        // Slow path: need to suspend
        let (element, error): (Element?, Async.Channel<Element>.Error?) = await withTaskCancellationHandler {
            await withUnsafeContinuation { (continuation: UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>) in
                let action = storage.withLock { state in
                    state.receive.wait(continuation)
                }

                switch action {
                case .val(let element):
                    continuation.resume(returning: (element, nil))
                case .end:
                    continuation.resume(returning: (nil, nil))
                case .wait:
                    // Continuation stored, will be resumed by send/close/stop
                    break
                }
            }
        } onCancel: {
            // Extract continuation under lock, resume outside
            let stopAction = storage.withLock { state in
                state.receive.stop()
            }

            if case .stop(let cont) = stopAction {
                cont.resume(returning: (nil, .cancelled))
            }
        }

        if let error { throw error }
        return element
    }

    /// Poll for an element without suspending.
    ///
    /// - Returns: The next element if available, `nil` if the buffer is empty.
    ///
    /// ## Semantics
    /// - Returns `.some(element)` if buffer has an element
    /// - Returns `nil` if buffer is empty, regardless of closed state
    /// - Never throws; cancellation is irrelevant because it never suspends
    /// - `nil` means "nothing available now," not "closed"
    @inlinable
    public func poll() -> Element? {
        storage.withLock { state in
            state.receive.poll()
        }
    }
}

// MARK: - Query

extension Async.Channel.Unbounded.Receiver {
    /// Whether the channel has been closed.
    ///
    /// Returns true when no further elements can be enqueued.
    /// This is a view of the same channel closure state as `Sender.closed`.
    ///
    /// Note: Even when `true`, `receive()` may still return elements
    /// if the buffer is not yet drained.
    public var closed: Bool {
        storage.withLock { $0.closed }
    }
}

// MARK: - AsyncSequence View

extension Async.Channel.Unbounded.Receiver {
    /// Returns an AsyncSequence view for iteration.
    ///
    /// ```swift
    /// for try await value in receiver.elements {
    ///     process(value)
    /// }
    /// ```
    public var elements: Async.Channel<Element>.Unbounded.Elements {
        Async.Channel<Element>.Unbounded.Elements(storage: storage)
    }
}

extension Async.Channel.Unbounded {
    /// An AsyncSequence view over an unbounded channel receiver.
    public struct Elements: AsyncSequence, @unchecked Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }

        public func makeAsyncIterator() -> Iterator {
            Iterator(storage: storage)
        }
    }
}

extension Async.Channel.Unbounded.Elements {
    /// Iterator for the AsyncSequence view.
    public struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Unbounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Unbounded.Storage) {
            self.storage = storage
        }

        @inlinable
        public mutating func next() async throws(Async.Channel<Element>.Error) -> Element? {
            // Capture storage to avoid capturing self in @Sendable closure
            let storage = self.storage

            // Fast path: try immediate receive
            let fastAction = storage.withLock { state in
                state.receive.take()
            }

            switch fastAction {
            case .val(let element):
                return element
            case .end:
                return nil
            case .wait:
                break
            }

            // Check cancellation before entering slow path
            if Task.isCancelled {
                throw .cancelled
            }

            // Slow path: need to suspend
            let (element, error): (Element?, Async.Channel<Element>.Error?) = await withTaskCancellationHandler {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>) in
                    let action = storage.withLock { state in
                        state.receive.wait(continuation)
                    }

                    switch action {
                    case .val(let element):
                        continuation.resume(returning: (element, nil))
                    case .end:
                        continuation.resume(returning: (nil, nil))
                    case .wait:
                        break
                    }
                }
            } onCancel: {
                let stopAction = storage.withLock { state in
                    state.receive.stop()
                }

                if case .stop(let cont) = stopAction {
                    cont.resume(returning: (nil, .cancelled))
                }
            }

            if let error { throw error }
            return element
        }
    }
}

#endif  // !hasFeature(Embedded)
