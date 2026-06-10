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

    import Queue_Primitives
    public import Ownership_Primitives
    import Column_Primitives
    public import Buffer_Ring_Primitive
    public import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// A receiver handle for a bounded channel.
        ///
        /// `Receiver` enforces a single-suspended-receiver invariant: at most one
        /// task may be suspended in `receive()` at a time. Concurrent suspended
        /// receives trigger a precondition failure in `State.suspend(continuation:)`.
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

    extension Async.Channel.Bounded.Receiver where Element: ~Copyable {
        /// Receive the next element from the channel.
        ///
        /// Suspends if the buffer is empty until an element becomes available
        /// or the channel is closed and drained.
        ///
        /// - Returns: The next element, or `nil` if the channel is closed and drained.
        /// - Throws: `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
        // WORKAROUND: @_optimize(none) prevents CopyPropagation ownership
        // verification crash on `switch consume` of ~Copyable enum in async context.
        // TRACKING: Not yet filed upstream.
        // WHEN TO REMOVE: When the CopyPropagation crash is fixed upstream.
        @_optimize(none)
        @inlinable
        nonisolated(nonsending)
            public func receive() async throws(Async.Channel<Element>.Error) -> Element?
        {
            // Fast path: try immediate receive
            let fastAction = storage.withLock { state in
                state.receive()
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
                break  // Fall through to slow path
            }

            // Slow path: need to suspend
            // Element delivery uses Ownership.Slot — continuation carries Signal only.
            let signal: Async.Channel<Element>.Bounded.State.Receive.Signal = await withTaskCancellationHandler {
                await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Bounded.State.Receive.Signal, Never>) in
                    let continuation = unsafe Async.Continuation.Unsafe(raw)
                    let action = storage.withLock { state in
                        state.suspend(continuation: continuation)
                    }
                    Async.Channel<Element>.Bounded.Storage.handleReceive(consume action, storage: storage, continuation: continuation)
                }
            } onCancel: {
                let action = storage.withLock { state in
                    state.cancel()
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

#endif  // !hasFeature(Embedded)
