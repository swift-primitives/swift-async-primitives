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

public import Ownership_Primitives
internal import Queue_Primitives

extension Async.Channel.Unbounded where Element: ~Copyable {
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
    /// `Receiver` is `Sendable` - it may be moved to another task
    /// for the canonical "handoff to consumer task" pattern. The mutex guards
    /// all state access. Concurrent suspension is caught by precondition.
    public struct Receiver: ~Copyable, Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }
    }
}

// MARK: - Receive Operations

extension Async.Channel.Unbounded.Receiver where Element: ~Copyable {
    /// Receive the next element from the channel.
    ///
    /// Suspends if the buffer is empty until an element becomes available
    /// or the channel is closed and drained.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation context for the operation.
    ///
    /// - Returns: The next element, or `nil` if the channel is closed and drained.
    /// - Throws: `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
    @inlinable
    public func receive(
        isolation: isolated (any Actor)? = #isolation
    ) async throws(Async.Channel<Element>.Error) -> Element? {
        // Fast path: try immediate receive
        let fastAction = storage.withLock { state in
            state.receive()
        }

        switch consume fastAction {
        case .val(let element):
            return element
        case .end:
            return nil
        case .wait:
            break // Fall through to slow path
        case .cancelled:
            throw .cancelled
        }

        // Check cancellation before entering slow path
        if Task.isCancelled {
            throw .cancelled
        }

        // Slow path: need to suspend
        // Element delivery uses Ownership.Slot — continuation carries Signal only.
        let signal: Async.Channel<Element>.Unbounded.State.Receive.Signal = await withTaskCancellationHandler {
            await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Unbounded.State.Receive.Signal, Never>) in
                let continuation = unsafe Async.Continuation.Unsafe(raw)
                let action = storage.withLock { state in
                    state.wait(continuation)
                }

                switch consume action {
                case .val(let element):
                    _ = storage.deliverySlot.store(element)
                    continuation.resume(returning: .delivered)
                case .end:
                    continuation.resume(returning: .closed)
                case .wait:
                    // Continuation stored, will be resumed by send/close/stop
                    break
                case .cancelled:
                    continuation.resume(returning: .cancelled)
                }
            }
        } onCancel: {
            // Extract continuation under lock, resume outside
            let stopAction = storage.withLock { state in
                state.stop()
            }

            if case .stop(let cont) = stopAction {
                cont.resume(returning: .cancelled)
            }
        }

        switch signal {
        case .delivered: return storage.deliverySlot.take()
        case .closed: return nil
        case .cancelled: throw .cancelled
        }
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
            state.poll()
        }
    }
}

// MARK: - Query

extension Async.Channel.Unbounded.Receiver where Element: ~Copyable {
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
    /// Available only when `Element` is `Copyable` (required by `AsyncSequence`).
    /// For `~Copyable` elements, use `receive()` directly in a while loop.
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
    public struct Elements: AsyncSequence, Sendable {
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
    public struct Iterator: AsyncIteratorProtocol, Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Unbounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Unbounded.Storage) {
            self.storage = storage
        }

        @inlinable
        public mutating func next(
            isolation: isolated (any Actor)? = #isolation
        ) async throws(Async.Channel<Element>.Error) -> Element? {
            // Capture storage to avoid capturing self in @Sendable closure
            let storage = self.storage

            // Fast path: try immediate receive
            let fastAction = storage.withLock { state in
                state.receive()
            }

            switch consume fastAction {
            case .val(let element):
                return element
            case .end:
                return nil
            case .wait:
                break
            case .cancelled:
                throw .cancelled
            }

            // Check cancellation before entering slow path
            if Task.isCancelled {
                throw .cancelled
            }

            // Slow path: need to suspend
            // Element delivery uses Ownership.Slot — continuation carries Signal only.
            let signal: Async.Channel<Element>.Unbounded.State.Receive.Signal = await withTaskCancellationHandler {
                await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Unbounded.State.Receive.Signal, Never>) in
                    let continuation = unsafe Async.Continuation.Unsafe(raw)
                    let action = storage.withLock { state in
                        state.wait(continuation)
                    }

                    switch consume action {
                    case .val(let element):
                        _ = storage.deliverySlot.store(element)
                        continuation.resume(returning: .delivered)
                    case .end:
                        continuation.resume(returning: .closed)
                    case .wait:
                        break
                    case .cancelled:
                        continuation.resume(returning: .cancelled)
                    }
                }
            } onCancel: {
                let stopAction = storage.withLock { state in
                    state.stop()
                }

                if case .stop(let cont) = stopAction {
                    cont.resume(returning: .cancelled)
                }
            }

            switch signal {
            case .delivered: return storage.deliverySlot.take()
            case .closed: return nil
            case .cancelled: throw .cancelled
            }
        }
    }
}

#endif  // !hasFeature(Embedded)
