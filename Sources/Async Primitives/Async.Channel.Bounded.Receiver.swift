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

public import Container_Primitives

extension Async.Channel.Bounded {
    /// A receiver handle for a bounded channel.
    ///
    /// `Receiver` enforces a single-suspended-receiver invariant: at most one
    /// task may be suspended in `receive()` at a time. Concurrent suspended
    /// receives trigger a precondition failure in `State.receiveSuspended`.
    ///
    /// ## Usage
    /// ```swift
    /// let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 10)
    ///
    /// // Receive elements (may suspend if buffer empty)
    /// while let value = try await receiver.receive() {
    ///     process(value)
    /// }
    ///
    /// // Or iterate via AsyncSequence view
    /// for try await value in receiver.elements {
    ///     process(value)
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// `Receiver` is `@unchecked Sendable` due to Swift limitations (tuples
    /// cannot contain `~Copyable` types). The single-consumer invariant is
    /// enforced via runtime precondition, not compile-time constraints.
    /// Violating this invariant is a programmer error.
    public struct Receiver: @unchecked Sendable {
        @usableFromInline
        let storage: Storage

        /// Marker to make this type non-Sendable in practice.
        /// The @unchecked Sendable is only to allow tuple returns;
        /// users should treat this as non-Sendable.
        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }
    }
}

// MARK: - Receive Operations

extension Async.Channel.Bounded.Receiver {
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
            state.tryReceive()
        }

        switch fastAction {
        case .returnElement(let element, let resumeSender, var cancelled):
            // Resume cancelled senders first (minimizes stuck time)
            while let c = cancelled.take.front {
                c.resume(returning: .cancelled)
            }
            resumeSender?.resume(returning: nil)
            return element
        case .returnNil:
            return nil
        case .rejectCancelled:
            throw .cancelled
        case .suspend:
            break // Fall through to slow path
        }

        // Slow path: need to suspend
        let (element, error): (Element?, Async.Channel<Element>.Error?) = await withTaskCancellationHandler {
            await withUnsafeContinuation { (continuation: UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>) in
                let action = storage.withLock { state in
                    state.receiveSuspended(continuation: continuation)
                }

                switch action {
                case .returnElement(let element, let resumeSender, var cancelled):
                    // Resume cancelled senders first (minimizes stuck time)
                    while let c = cancelled.take.front {
                        c.resume(returning: .cancelled)
                    }
                    resumeSender?.resume(returning: nil)
                    continuation.resume(returning: (element, nil))
                case .returnNil:
                    continuation.resume(returning: (nil, nil))
                case .rejectCancelled:
                    continuation.resume(returning: (nil, .cancelled))
                case .suspend:
                    // Continuation stored, will be resumed later
                    break
                }
            }
        } onCancel: {
            let action = storage.withLock { state in
                state.receiveCancelled()
            }
            switch action {
            case .resumeWithCancellation(let continuation):
                continuation.resume(returning: (nil, .cancelled))
            case .none:
                break
            }
        }

        if let error { throw error }
        return element
    }

    /// Try to receive an element without suspending.
    ///
    /// - Returns: The next element if available, `nil` if the buffer is empty.
    @inlinable
    public func tryReceive() -> Element? {
        let action = storage.withLock { state in
            state.tryReceive()
        }

        switch action {
        case .returnElement(let element, let resumeSender, var cancelled):
            // Resume cancelled senders first (minimizes stuck time)
            while let c = cancelled.take.front {
                c.resume(returning: .cancelled)
            }
            resumeSender?.resume(returning: nil)
            return element
        case .returnNil, .rejectCancelled, .suspend:
            return nil
        }
    }
}

// MARK: - Query

extension Async.Channel.Bounded.Receiver {
    /// Whether the channel has been closed.
    ///
    /// Note: Even when `true`, `receive()` may still return elements
    /// if the buffer is not yet drained.
    public var isClosed: Bool {
        storage.withLock { $0.isClosed }
    }
}

// MARK: - AsyncSequence View

extension Async.Channel.Bounded.Receiver {
    /// Returns an AsyncSequence view for iteration.
    ///
    /// ```swift
    /// for try await value in receiver.elements {
    ///     process(value)
    /// }
    /// ```
    public var elements: Async.Channel<Element>.Bounded.Elements {
        Async.Channel<Element>.Bounded.Elements(storage: storage)
    }
}

extension Async.Channel.Bounded {
    /// An AsyncSequence view over a bounded channel receiver.
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

extension Async.Channel.Bounded.Elements {
    /// Iterator for the AsyncSequence view.
    public struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
            self.storage = storage
        }

        @inlinable
        public mutating func next() async throws(Async.Channel<Element>.Error) -> Element? {
            // Capture storage to avoid capturing self in @Sendable closure
            let storage = self.storage

            // Fast path: try immediate receive
            let fastAction = storage.withLock { state in
                state.tryReceive()
            }

            switch fastAction {
            case .returnElement(let element, let resumeSender, var cancelled):
                while let c = cancelled.take.front {
                    c.resume(returning: .cancelled)
                }
                resumeSender?.resume(returning: nil)
                return element
            case .returnNil:
                return nil
            case .rejectCancelled:
                throw .cancelled
            case .suspend:
                break
            }

            // Slow path: need to suspend
            let (element, error): (Element?, Async.Channel<Element>.Error?) = await withTaskCancellationHandler {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>) in
                    let action = storage.withLock { state in
                        state.receiveSuspended(continuation: continuation)
                    }

                    switch action {
                    case .returnElement(let element, let resumeSender, var cancelled):
                        while let c = cancelled.take.front {
                            c.resume(returning: .cancelled)
                        }
                        resumeSender?.resume(returning: nil)
                        continuation.resume(returning: (element, nil))
                    case .returnNil:
                        continuation.resume(returning: (nil, nil))
                    case .rejectCancelled:
                        continuation.resume(returning: (nil, .cancelled))
                    case .suspend:
                        break
                    }
                }
            } onCancel: {
                let action = storage.withLock { state in
                    state.receiveCancelled()
                }
                switch action {
                case .resumeWithCancellation(let continuation):
                    continuation.resume(returning: (nil, .cancelled))
                case .none:
                    break
                }
            }

            if let error { throw error }
            return element
        }
    }
}
