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
    public import Deque_Primitives
    public import Column_Primitives
    public import Buffer_Ring_Primitive
    public import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// Pure state machine for bounded channel operations.
        ///
        /// This state machine contains no side effects. All operations return
        /// `Action` values that describe what the caller should do.
        ///
        /// State is stored as flat properties rather than an enum with associated
        /// values. This eliminates the per-mutation extract-reconstruct cycle
        /// (and the `.modifying` sentinel needed to prevent CoW during extraction).
        @usableFromInline
        struct State: ~Copyable {
            @usableFromInline
            var status: Status
            @usableFromInline
            var buffer: Deque<Column.Ring<Element>>
            @usableFromInline
            var senders: Deque<Column.Ring<Sender>>
            @usableFromInline
            var receiver: Receiver?
            @usableFromInline
            let capacity: Index<Element>.Count
            @usableFromInline
            var cancelledReceiver: Bool = false

            @usableFromInline
            init(capacity: Index<Element>.Count) {
                self.status = .open
                self.buffer = Deque()
                self.senders = Deque()
                self.receiver = nil
                self.capacity = capacity
            }
        }
    }

    // MARK: - Status

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        @usableFromInline
        enum Status: Sendable {
            /// Channel is open and operational.
            case open

            /// Channel is closed but may still have buffered elements.
            case closed

            /// Channel is finished - no more elements, fully drained.
            case finished
        }
    }

    // MARK: - Sender

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        // `~Copyable`: stores a `Send.Continuation` (now `~Copyable`), so the
        // container that owns it must be single-use too.
        @usableFromInline
        struct Sender: ~Copyable, Sendable {
            @usableFromInline
            let slot: Ownership.Slot<Element>
            @usableFromInline
            let continuation: Send.Continuation
            @usableFromInline
            let flag: Async.Waiter.Flag

            @usableFromInline
            init(
                slot: Ownership.Slot<Element>,
                continuation: consuming Send.Continuation,
                flag: Async.Waiter.Flag
            ) {
                self.slot = slot
                self.continuation = continuation
                self.flag = flag
            }
        }
    }

    // MARK: - Receiver

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        // `~Copyable`: stores a `Receive.Continuation` (now `~Copyable`).
        @usableFromInline
        struct Receiver: ~Copyable, Sendable {
            @usableFromInline
            let continuation: Receive.Continuation

            @usableFromInline
            init(continuation: consuming Receive.Continuation) {
                self.continuation = continuation
            }
        }
    }

    // MARK: - Sender Queue Helpers

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        /// Pops the next non-cancelled sender from the queue.
        ///
        /// Flagged senders are skipped and their continuations collected into
        /// `cancelled` (lazily allocated on the first hit). The collection rides an
        /// `inout` optional rather than a closure: the move-only deque cannot be
        /// consumed after a closure captures it ([MEM-OWN-017] — the F-3 wall).
        @usableFromInline
        mutating func next(
            collectingCancelledInto cancelled: inout Deque<Column.Ring<Send.Continuation>>?
        ) -> Sender? {
            while let sender = senders.take(from: .front) {
                if sender.flag.isFlagged {
                    if cancelled == nil { cancelled = Deque<Column.Ring<Send.Continuation>>() }
                    cancelled?.push(sender.continuation, to: .back)
                    continue
                }
                return sender
            }
            return nil
        }
    }

    // MARK: - Send

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        @usableFromInline
        enum Send {}
    }

    extension Async.Channel.Bounded.State.Send where Element: ~Copyable {
        /// Continuation type for send operations.
        ///
        /// Returns nil on success, Error on failure.
        @usableFromInline
        typealias Continuation = Async.Continuation<Async.Channel<Element>.Error?>.Unsafe

        /// Result of `send` — fast-path decision.
        ///
        /// Element is handled via the caller's `inout Element?`: taken on
        /// deliver/buffer paths, left in Optional on suspend/reject.
        @usableFromInline
        enum Decision: ~Copyable {
            /// Deliver the element directly to a waiting receiver.
            /// Element was taken from the Optional inside send.
            case deliverToReceiver(Async.Channel<Element>.Bounded.State.Receive.Continuation, Element)

            /// Element was buffered successfully (taken from Optional).
            case buffered

            /// Sender must suspend and wait. Element remains in the caller's
            /// Optional. The flag is pre-created for cancellation signaling
            /// (shared between queue entry and onCancel handler).
            case suspend(flag: Async.Waiter.Flag)

            /// Channel is closed, reject the send.
            /// Element remains in the caller's Optional (cleaned up by deinit).
            case rejectClosed
        }

        /// Result of `suspend(flag:slot:continuation:)` — slow-path action.
        ///
        /// Element is handled via Ownership.Slot (taken on deliver/buffer,
        /// stored in queue on suspend, cleaned up by Slot deinit on reject).
        @usableFromInline
        enum Action: ~Copyable {
            /// Deliver the element directly to a waiting receiver.
            /// `sender`: the suspending sender's continuation, handed back to
            /// be resumed outside the lock.
            case deliverToReceiver(Async.Channel<Element>.Bounded.State.Receive.Continuation, Element, sender: Async.Channel<Element>.Bounded.State.Send.Continuation)

            /// Element was buffered successfully.
            case buffered(sender: Async.Channel<Element>.Bounded.State.Send.Continuation)

            /// Continuation stored, sender is now suspended.
            case suspended

            /// Channel is closed, reject the send.
            case rejectClosed(sender: Async.Channel<Element>.Bounded.State.Send.Continuation)

            /// Sender was already cancelled before suspension.
            case rejectCancelled(sender: Async.Channel<Element>.Bounded.State.Send.Continuation)
        }
    }

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        /// Attempt a synchronous send (non-blocking).
        ///
        /// The element is in the caller's `inout Element?`. On deliver/buffer
        /// paths it is taken from the Optional. On suspend/reject, the element
        /// remains in the Optional for the caller to handle.
        @usableFromInline
        mutating func send(_ element: inout Element?) -> Send.Decision {
            switch status {
            case .open:
                // If a receiver is waiting, deliver directly.
                // Move the receiver out of storage before consuming its
                // continuation (the continuation is now `~Copyable`).
                if let receiver = self.receiver.take() {
                    guard let taken = element.take() else {
                        preconditionFailure("Async.Channel.Bounded.State.send(_:): element slot was empty")
                    }
                    return .deliverToReceiver(receiver.continuation, taken)
                }

                // If buffer has space, add to buffer
                if buffer.count < capacity {
                    guard let taken = element.take() else {
                        preconditionFailure("Async.Channel.Bounded.State.send(_:): element slot was empty")
                    }
                    buffer.push(taken, to: .back)
                    return .buffered
                }

                // Buffer full — element stays in Optional for slow-path staging
                return .suspend(flag: Async.Waiter.Flag())

            case .closed, .finished:
                return .rejectClosed
            }
        }

        /// Register a sender that will suspend.
        ///
        /// The element is in the provided Ownership.Slot. On deliver/buffer paths
        /// it is taken from the Slot. On suspend, the Slot reference is stored in
        /// the sender queue. On reject, the Slot's deinit handles cleanup.
        @usableFromInline
        mutating func suspend(
            flag: Async.Waiter.Flag,
            slot: Ownership.Slot<Element>,
            continuation: consuming Send.Continuation
        ) -> Send.Action {
            // Pre-registration check: cancellation arrived before suspension
            if flag.cancelled {
                return .rejectCancelled(sender: continuation)
            }

            switch status {
            case .open:
                // Double-check: receiver might have arrived
                if let receiver = self.receiver.take() {
                    let element = slot.take(__unchecked: ())
                    return .deliverToReceiver(receiver.continuation, element, sender: continuation)
                }

                // Double-check: space might be available
                if buffer.count < capacity {
                    buffer.push(slot.take(__unchecked: ()), to: .back)
                    return .buffered(sender: continuation)
                }

                // Enqueue waiter — flag shared with onCancel handler.
                // The continuation is moved into the queued Sender here; the other
                // paths hand it back inside the returned action for the caller to
                // resume outside the lock.
                senders.push(Sender(slot: slot, continuation: continuation, flag: flag), to: .back)
                return .suspended

            case .closed, .finished:
                return .rejectClosed(sender: continuation)
            }
        }

        /// Reap all flagged (cancelled) senders from the queue.
        ///
        /// Drains the queue, collecting flagged entries' continuations and
        /// re-enqueuing non-flagged entries. Follows the Waiter `reapFlagged()` pattern.
        /// Flagged senders' slots are dropped — `Slot.deinit` cleans up the element.
        @usableFromInline
        mutating func reap() -> Deque<Column.Ring<Send.Continuation>> {
            var cancelled = Deque<Column.Ring<Send.Continuation>>()
            var survivors = Deque<Column.Ring<Sender>>()
            while let sender = senders.take(from: .front) {
                if sender.flag.isFlagged {
                    cancelled.push(sender.continuation, to: .back)
                } else {
                    survivors.push(sender, to: .back)
                }
            }
            senders = survivors
            return cancelled
        }
    }

    // MARK: - Receive

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        @usableFromInline
        enum Receive {}
    }

    extension Async.Channel.Bounded.State.Receive where Element: ~Copyable {
        /// Lightweight signal carried through the continuation.
        ///
        /// Element delivery happens via Ownership.Slot, not through the continuation.
        @usableFromInline
        enum Signal: Sendable {
            /// An element was delivered via the delivery slot.
            case delivered
            /// The channel is closed and drained.
            case closed
            /// The operation was cancelled.
            case cancelled
        }

        /// Continuation type for receive operations.
        ///
        /// Carries Signal (Copyable) — element travels via Ownership.Slot.
        @usableFromInline
        typealias Continuation = Async.Continuation<Signal>.Unsafe

        @usableFromInline
        enum Action: ~Copyable {
            /// Return the element immediately.
            /// `resumeSender`: continuation of the sender that provided this element.
            /// `cancelled`: continuations of cancelled senders skipped during pop.
            /// Nil when no cancellations occurred (the common case), avoiding
            /// a per-receive Deque heap allocation.
            /// `receiver`: the suspending receiver's continuation on the slow
            /// path (nil on the fast path, which has no continuation), handed
            /// back to be resumed outside the lock.
            case returnElement(
                Element,
                resumeSender: Async.Channel<Element>.Bounded.State.Send.Continuation?,
                cancelled: Deque<Column.Ring<Async.Channel<Element>.Bounded.State.Send.Continuation>>?,
                receiver: Async.Channel<Element>.Bounded.State.Receive.Continuation?
            )

            /// Receiver must suspend and wait.
            case suspend

            /// Channel is closed and drained.
            case returnNil(receiver: Async.Channel<Element>.Bounded.State.Receive.Continuation?)

            /// Receiver was already cancelled before suspension.
            case rejectCancelled(receiver: Async.Channel<Element>.Bounded.State.Receive.Continuation?)
        }

        // `~Copyable`: `.resumeWithCancellation` carries a `Receive.Continuation`.
        @usableFromInline
        enum Cancel: ~Copyable, Sendable {
            case resumeWithCancellation(Async.Channel<Element>.Bounded.State.Receive.Continuation)
            case none
        }
    }

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        /// Attempt a synchronous receive (non-blocking).
        @usableFromInline
        mutating func receive() -> Receive.Action {
            switch status {
            case .open:
                precondition(receiver == nil, "Single-consumer invariant violated")

                // Lazy: allocated only when a cancelled sender is actually found
                // (inside `next` — the inout-collection shape, [MEM-OWN-017]).
                var cancelled: Deque<Column.Ring<Send.Continuation>>? = nil

                // If buffer has elements
                if let element = buffer.take(from: .front) {
                    // Wake up a waiting sender if any (skipping cancelled)
                    if let sender = next(collectingCancelledInto: &cancelled) {
                        buffer.push(sender.slot.take(__unchecked: ()), to: .back)
                        return .returnElement(element, resumeSender: sender.continuation, cancelled: cancelled, receiver: nil)
                    }
                    return .returnElement(element, resumeSender: nil, cancelled: cancelled, receiver: nil)
                }

                // If there are waiting senders, take directly from them (skipping cancelled)
                if let sender = next(collectingCancelledInto: &cancelled) {
                    return .returnElement(sender.slot.take(__unchecked: ()), resumeSender: sender.continuation, cancelled: cancelled, receiver: nil)
                }

                // Nothing available, would need to suspend
                return .suspend

            case .closed:
                if let element = buffer.take(from: .front) {
                    if buffer.isEmpty {
                        status = .finished
                    }
                    return .returnElement(element, resumeSender: nil, cancelled: nil, receiver: nil)
                }
                status = .finished
                return .returnNil(receiver: nil)

            case .finished:
                return .returnNil(receiver: nil)
            }
        }

        /// Register a receiver that will suspend.
        @usableFromInline
        mutating func suspend(
            continuation: consuming Receive.Continuation
        ) -> Receive.Action {
            // Check if already cancelled
            if cancelledReceiver {
                cancelledReceiver = false
                return .rejectCancelled(receiver: continuation)
            }

            switch status {
            case .open:
                precondition(receiver == nil, "Single-consumer invariant violated")

                // Lazy: allocated only when a cancelled sender is actually found
                // (inside `next` — the inout-collection shape, [MEM-OWN-017]).
                var cancelled: Deque<Column.Ring<Send.Continuation>>? = nil

                // Double-check: element might be available.
                // The race paths hand the continuation back inside the action so
                // the caller resumes it outside the lock; the store path below
                // moves it into the stored Receiver instead.
                if let element = buffer.take(from: .front) {
                    if let sender = next(collectingCancelledInto: &cancelled) {
                        buffer.push(sender.slot.take(__unchecked: ()), to: .back)
                        return .returnElement(element, resumeSender: sender.continuation, cancelled: cancelled, receiver: continuation)
                    }
                    return .returnElement(element, resumeSender: nil, cancelled: cancelled, receiver: continuation)
                }

                if let sender = next(collectingCancelledInto: &cancelled) {
                    return .returnElement(sender.slot.take(__unchecked: ()), resumeSender: sender.continuation, cancelled: cancelled, receiver: continuation)
                }

                // Store receiver
                receiver = Receiver(continuation: continuation)
                return .suspend

            case .closed:
                if let element = buffer.take(from: .front) {
                    if buffer.isEmpty {
                        status = .finished
                    }
                    return .returnElement(element, resumeSender: nil, cancelled: nil, receiver: continuation)
                }
                status = .finished
                return .returnNil(receiver: continuation)

            case .finished:
                return .returnNil(receiver: continuation)
            }
        }

        /// Handle receiver cancellation.
        @usableFromInline
        mutating func cancel() -> Receive.Cancel {
            switch status {
            case .open:
                if let receiver = self.receiver.take() {
                    return .resumeWithCancellation(receiver.continuation)
                }
                // Receiver not suspended yet - mark as cancelled
                cancelledReceiver = true
                return .none

            case .closed, .finished:
                return .none
            }
        }
    }

    // MARK: - Close

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        @usableFromInline
        struct Close: ~Copyable, Sendable {
            // `var` (not `let`) so the caller can `take()` the continuation out
            // to resume it — a `~Copyable` value cannot be resumed in place.
            @usableFromInline
            var receiverToResume: Receive.Continuation?
            @usableFromInline
            var sendersToCancel: Deque<Column.Ring<Send.Continuation>>

            @usableFromInline
            init(
                receiverToResume: consuming Receive.Continuation?,
                sendersToCancel: consuming Deque<Column.Ring<Send.Continuation>>
            ) {
                self.receiverToResume = receiverToResume
                self.sendersToCancel = sendersToCancel
            }
        }

        @usableFromInline
        mutating func close() -> Close {
            switch status {
            case .open:
                // Collect senders to cancel (drain the queue)
                var sendersToCancel = Deque<Column.Ring<Send.Continuation>>()
                while let sender = senders.take(from: .front) {
                    sendersToCancel.push(sender.continuation, to: .back)
                }

                // If buffer is empty and receiver is waiting, resume with nil
                if buffer.isEmpty {
                    if let receiver = self.receiver.take() {
                        status = .finished
                        return Close(
                            receiverToResume: receiver.continuation,
                            sendersToCancel: sendersToCancel
                        )
                    }
                    status = .finished
                } else {
                    status = .closed
                }
                return Close(receiverToResume: nil, sendersToCancel: sendersToCancel)

            case .closed, .finished:
                return Close(
                    receiverToResume: nil,
                    sendersToCancel: Deque<Column.Ring<Send.Continuation>>()
                )
            }
        }
    }

    // MARK: - Query

    extension Async.Channel.Bounded.State where Element: ~Copyable {
        @usableFromInline
        var isClosed: Bool {
            switch status {
            case .open:
                return false

            case .closed, .finished:
                return true
            }
        }
    }

#endif  // !hasFeature(Embedded)
