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
public import Queue_Primitives

extension Async.Channel.Bounded where Element: ~Copyable {
    /// A receiver handle for a bounded channel.
    ///
    /// `Receiver` enforces a single-suspended-receiver invariant: at most one
    /// task may be suspended in `receive()` at a time. Concurrent suspended
    /// receives trigger a precondition failure in `State.receiveSuspended`.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Bounded(capacity: 10)
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

extension Async.Channel.Bounded.Receiver where Element: ~Copyable {
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
            state.tryReceive()
        }

        switch consume fastAction {
        case .returnElement(let element, let resumeSender, let cancelled):
            // Resume cancelled senders first (minimizes stuck time)
            if var cancelled {
                while let c = cancelled.take(from: .front) {
                    c.resume(returning: .cancelled)
                }
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
        // Element delivery uses Ownership.Slot — continuation carries Signal only.
        let signal: Async.Channel<Element>.Bounded.State.Receive.Signal = await withTaskCancellationHandler {
            await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Bounded.State.Receive.Signal, Never>) in
                let continuation = unsafe Async.Continuation.Unsafe(raw)
                let action = storage.withLock { state in
                    state.receiveSuspended(continuation: continuation)
                }

                switch consume action {
                case .returnElement(let element, let resumeSender, let cancelled):
                    // Resume cancelled senders first (minimizes stuck time)
                    if var cancelled {
                        while let c = cancelled.take(from: .front) {
                            c.resume(returning: .cancelled)
                        }
                    }
                    resumeSender?.resume(returning: nil)
                    storage.deliverySlot.store(element)
                    continuation.resume(returning: .delivered)
                case .returnNil:
                    continuation.resume(returning: .closed)
                case .rejectCancelled:
                    continuation.resume(returning: .cancelled)
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
                continuation.resume(returning: .cancelled)
            case .none:
                break
            }
        }

        switch signal {
        case .delivered: return storage.deliverySlot.take()
        case .closed: return nil
        case .cancelled: throw .cancelled
        }
    }

    /// Accessor for receive operation variants.
    public var receive: Receive { Receive(storage: storage) }
}

// MARK: - Receive Accessor

extension Async.Channel.Bounded.Receiver where Element: ~Copyable {
    /// Receive operation accessor with variants.
    public struct Receive: Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
            self.storage = storage
        }

        /// Receive an element without suspending.
        ///
        /// - Returns: The next element if available, `nil` if the channel is closed and drained.
        /// - Throws: `.empty` if the buffer is empty, `.cancelled` if the task was cancelled.
        @inlinable
        public func immediate() throws(Async.Channel<Element>.Error) -> Element? {
            let action = storage.withLock { state in
                state.tryReceive()
            }

            switch consume action {
            case .returnElement(let element, let resumeSender, var cancelled):
                // Resume cancelled senders first (minimizes stuck time)
                while let c = cancelled?.take(from: .front) {
                    c.resume(returning: .cancelled)
                }
                resumeSender?.resume(returning: nil)
                return element
            case .returnNil:
                return nil
            case .rejectCancelled:
                throw .cancelled
            case .suspend:
                throw .empty
            }
        }
    }
}

// MARK: - Query

extension Async.Channel.Bounded.Receiver where Element: ~Copyable {
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
    /// Available only when `Element` is `Copyable` (required by `AsyncSequence`).
    /// For `~Copyable` elements, use `receive()` directly in a while loop.
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

extension Async.Channel.Bounded.Elements {
    /// Iterator for the AsyncSequence view.
    public struct Iterator: AsyncIteratorProtocol, Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
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
                state.tryReceive()
            }

            switch consume fastAction {
            case .returnElement(let element, let resumeSender, let cancelled):
                if var cancelled {
                    while let c = cancelled.take(from: .front) {
                        c.resume(returning: .cancelled)
                    }
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
            let signal: Async.Channel<Element>.Bounded.State.Receive.Signal = await withTaskCancellationHandler {
                await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Bounded.State.Receive.Signal, Never>) in
                    let continuation = unsafe Async.Continuation.Unsafe(raw)
                    let action = storage.withLock { state in
                        state.receiveSuspended(continuation: continuation)
                    }

                    switch action {
                    case .returnElement(let element, let resumeSender, let cancelled):
                        if var cancelled {
                            while let c = cancelled.take(from: .front) {
                                c.resume(returning: .cancelled)
                            }
                        }
                        resumeSender?.resume(returning: nil)
                        storage.deliverySlot.store(element)
                        continuation.resume(returning: .delivered)
                    case .returnNil:
                        continuation.resume(returning: .closed)
                    case .rejectCancelled:
                        continuation.resume(returning: .cancelled)
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
                    continuation.resume(returning: .cancelled)
                case .none:
                    break
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
