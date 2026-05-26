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

    public import Async_Waiter_Primitives
    public import Ownership_Primitives
    internal import Queue_Primitives
    internal import Queue_DoubleEnded_Primitives

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// A sender handle for a bounded channel.
        ///
        /// `Sender` is a Copyable, Sendable struct that allows sending elements
        /// to a bounded channel. Multiple senders can share the same channel
        /// by copying the handle (each copy shares the underlying storage).
        ///
        /// ## Auto-Close (ARC-Mediated)
        /// `Sender` wraps an internal `Handle` reference. **Copying a `Sender`
        /// increments the channel's sender-handle refcount**; dropping a copy
        /// decrements it. When the **last `Sender` copy across ALL tasks** is
        /// released and its `Handle` deinit runs, the channel automatically
        /// closes — pending receivers resume with `nil` (after buffer drains),
        /// suspended senders throw `.closed`.
        ///
        /// This auto-close is the ARC-mediated counterpart to explicit
        /// `close()`. The two paths converge on the same close action:
        ///
        /// - **Explicit**: `sender.close()` (or `ends.close()`) is called from
        ///   any sender; immediate close action.
        /// - **Implicit**: last `Sender` copy is released; `Handle.deinit`
        ///   triggers the close action.
        ///
        /// ### Capture in actor-isolated state
        /// A `Sender` captured in an `actor`'s stored property (or in a closure
        /// stored on an actor) has its `Handle.deinit` run on the **actor's
        /// executor** when the captured value is released. The deinit's close
        /// action acquires the channel's internal `Async.Mutex` (a non-actor
        /// lock); resumed continuations are scheduled, not synchronously
        /// invoked. There is no reentrancy hazard for actor-isolated state
        /// — the actor is not re-entered as part of the close path; any
        /// continuation that targets the same actor is enqueued via the
        /// runtime's normal scheduling.
        ///
        /// ## Usage
        /// ```swift
        /// var channel = Async.Channel<Int>.Bounded(capacity: 10)
        ///
        /// // Send elements (may suspend if buffer full)
        /// try await channel.sender.send(42)
        ///
        /// // Clone sender for another producer (ARC increments)
        /// let sender2 = channel.sender
        ///
        /// // Close explicitly (or let auto-close on last drop)
        /// channel.close()
        /// ```
        ///
        /// ## Thread Safety
        /// `Sender` is `Sendable` and can be shared across tasks/actors.
        public struct Sender: Sendable {
            @usableFromInline
            let handle: Handle

            @usableFromInline
            init(storage: Storage) {
                self.handle = Handle(storage: storage)
            }
        }
    }

    // MARK: - Handle (ARC-based auto-close)

    extension Async.Channel.Bounded.Sender where Element: ~Copyable {
        /// Internal handle that provides ARC-based auto-close.
        ///
        /// When the last reference to this handle is released, the channel
        /// automatically closes.
        @usableFromInline
        final class Handle: Sendable {
            @usableFromInline
            let storage: Async.Channel<Element>.Bounded.Storage

            @usableFromInline
            init(storage: Async.Channel<Element>.Bounded.Storage) {
                self.storage = storage
            }

            deinit {
                // Auto-close when last sender drops
                var closeAction = storage.withLock { state in
                    state.close()
                }

                // Resume receiver with nil (channel closed) - outside lock
                closeAction.receiverToResume?.resume(returning: .closed)

                // Cancel all waiting senders - outside lock
                while let continuation = closeAction.sendersToCancel.take(from: .front) {
                    continuation.resume(returning: .closed)
                }
            }
        }
    }

    // MARK: - Send Operations

    extension Async.Channel.Bounded.Sender where Element: ~Copyable {
        /// Send an element to the channel.
        ///
        /// Suspends if the buffer is full until space becomes available
        /// or the channel is closed.
        ///
        /// - Parameter element: The element to send.
        ///
        /// - Throws: `Async.Channel<Element>.Error.closed` if the channel is closed.
        ///           `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
        // WORKAROUND: @_optimize(none) — see Storage.handleSend workaround comment.
        @_optimize(none)
        @inlinable
        nonisolated(nonsending)
            public func send(
                _ element: consuming sending Element
            ) async throws(Async.Channel<Element>.Error)
        {
            // Stage element in a Sendable Slot for lock-boundary transfer.
            // Ownership.Slot is @unchecked Sendable — capturing it in the withLock
            // closure avoids region merge that inout Element? would cause.
            let slot = Ownership.Slot(consume element)
            let decision = handle.storage.withLock { state in
                var opt: Element? = slot.take()
                let d = state.send(&opt)
                if let remaining = opt.take() {
                    _ = slot.store(remaining)
                }
                return d
            }

            let flag: Async.Waiter.Flag
            switch consume decision {
            case .deliverToReceiver(let receiverCont, let element):
                _ = handle.storage.deliverySlot.store(element)
                receiverCont.resume(returning: Async.Channel<Element>.Bounded.State.Receive.Signal.delivered)
                return
            case .buffered:
                return
            case .rejectClosed:
                throw .closed
            case .suspend(let sendFlag):
                flag = sendFlag
            }

            let error: Async.Channel<Element>.Error? = await withTaskCancellationHandler {
                await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Error?, Never>) in
                    let continuation = unsafe Async.Continuation.Unsafe(raw)
                    let action = handle.storage.withLock { state in
                        state.suspend(flag: flag, slot: slot, continuation: continuation)
                    }

                    Async.Channel<Element>.Bounded.Storage.handleSend(consume action, storage: handle.storage, continuation: continuation)
                }
            } onCancel: {
                if flag.cancel() {
                    var cancelled = Deque<Async.Channel<Element>.Bounded.State.Send.Continuation>()
                    handle.storage.withLock { state in
                        cancelled = state.reap()
                    }
                    while let cont = cancelled.take(from: .front) {
                        cont.resume(returning: .cancelled)
                    }
                }
            }

            if let error { throw error }
        }

        /// Accessor for send operation variants.
        public var send: Send { Send(handle: handle) }
    }

    // MARK: - Lifecycle

    extension Async.Channel.Bounded.Sender where Element: ~Copyable {
        /// Close the channel, signaling no more elements will be sent.
        ///
        /// **Hybrid forced/graceful semantics**:
        ///
        /// - **Forced for senders**. Suspended `send(_:)` calls (waiting on a
        ///   full buffer) are immediately resumed with `Error.closed`; their
        ///   element drops on the floor. Future `send(_:)` calls throw
        ///   `Error.closed`. The closing party's intent overrides any
        ///   in-flight send.
        /// - **Graceful for receivers**. The buffer is **not flushed**.
        ///   Receivers calling `receive()` continue to see buffered elements
        ///   in FIFO order until the buffer is drained, only then receiving
        ///   `nil`. A receiver suspended at the moment of close (empty
        ///   buffer) resumes immediately with `nil`.
        ///
        /// `close()` is idempotent — calling it on an already-closed channel
        /// is a no-op.
        ///
        /// Concurrent semantics: any element pushed by a successful `send`
        /// that completed before `close()` acquired the storage lock is
        /// still observable by receivers; any `send` that hadn't yet
        /// acquired the lock will now throw `.closed`. The lock provides a
        /// linearization point.
        ///
        /// After this call:
        /// - Any pending `receive()` returns `nil` (if buffer empty)
        /// - Future `receive()` calls drain buffer then return `nil`
        /// - Future `send()` calls throw `Error.closed`
        /// - Pending `send()` calls throw `Error.closed`
        public func close() {
            var closeAction = handle.storage.withLock { state in
                state.close()
            }

            // Resume receiver with nil (channel closed) - outside lock
            closeAction.receiverToResume?.resume(returning: .closed)

            // Cancel all waiting senders - outside lock
            while let continuation = closeAction.sendersToCancel.take(from: .front) {
                continuation.resume(returning: .closed)
            }
        }

        /// Whether the channel has been closed.
        ///
        /// Note: Even when `true`, `receive()` may still return elements
        /// if the buffer is not yet drained.
        public var isClosed: Bool {
            handle.storage.withLock { $0.isClosed }
        }
    }

#endif  // !hasFeature(Embedded)
