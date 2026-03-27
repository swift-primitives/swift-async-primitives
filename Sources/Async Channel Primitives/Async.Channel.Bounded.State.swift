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
    /// Pure state machine for bounded channel operations.
    ///
    /// This state machine contains no side effects. All operations return
    /// `Action` values that describe what the caller should do.
    ///
    /// State is stored as flat properties rather than an enum with associated
    /// values. This eliminates the per-mutation extract-reconstruct cycle
    /// (and the `.modifying` sentinel needed to prevent CoW during extraction).
    @usableFromInline
    struct State: ~Copyable, @unchecked Sendable {
        @usableFromInline
        var status: Status
        @usableFromInline
        var buffer: Deque<Element>
        @usableFromInline
        var senders: Deque<Sender>
        @usableFromInline
        var receiver: Receiver?
        @usableFromInline
        let capacity: Index<Element>.Count
        @usableFromInline
        var nextId: UInt64 = 0
        @usableFromInline
        var cancelledSenders: Set<UInt64> = []
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
    @usableFromInline
    struct Sender: Sendable {
        @usableFromInline
        let id: UInt64
        @usableFromInline
        let slot: Ownership.Slot<Element>
        @usableFromInline
        let continuation: Send.Continuation

        @usableFromInline
        init(
            id: UInt64,
            slot: Ownership.Slot<Element>,
            continuation: Send.Continuation
        ) {
            self.id = id
            self.slot = slot
            self.continuation = continuation
        }
    }
}

// MARK: - Receiver

extension Async.Channel.Bounded.State where Element: ~Copyable {
    @usableFromInline
    struct Receiver: Sendable {
        @usableFromInline
        let continuation: Receive.Continuation

        @usableFromInline
        init(continuation: Receive.Continuation) {
            self.continuation = continuation
        }
    }
}

// MARK: - Sender Queue Helpers

extension Async.Channel.Bounded.State where Element: ~Copyable {
    /// Pops the next non-cancelled sender from the queue.
    ///
    /// Cancelled senders are skipped and their continuations resumed via the closure.
    /// The cancellation marker is consumed from `cancelledSenders` on skip.
    ///
    /// - Invariant: Each sender id is unique and appears at most once in the queue.
    @usableFromInline
    mutating func popNextSender(
        resumeCancelled: (Send.Continuation) -> Void
    ) -> Sender? {
        while let sender = senders.take(from: .front) {
            if cancelledSenders.remove(sender.id) != nil {
                resumeCancelled(sender.continuation)
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
    enum Send {
        /// Continuation type for send operations.
        /// Returns nil on success, Error on failure.
        @usableFromInline
        typealias Continuation = Async.Continuation<Async.Channel<Element>.Error?>.Unsafe

        /// Result of `trySend` — fast-path decision.
        /// Element is handled via the caller's `inout Element?`: taken on
        /// deliver/buffer paths, left in Optional on suspend/reject.
        @usableFromInline
        enum Decision: ~Copyable, @unchecked Sendable {
            /// Deliver the element directly to a waiting receiver.
            /// Element was taken from the Optional inside trySend.
            case deliverToReceiver(Receive.Continuation, Element)

            /// Element was buffered successfully (taken from Optional).
            case buffered

            /// Sender must suspend and wait. Element remains in the caller's
            /// Optional. The id is pre-generated for cancellation tracking
            /// (eliminates a separate lock acquisition).
            case suspend(id: UInt64)

            /// Channel is closed, reject the send.
            /// Element remains in the caller's Optional (cleaned up by deinit).
            case rejectClosed
        }

        /// Result of `sendSuspended` — slow-path action.
        /// Element is handled via Ownership.Slot (taken on deliver/buffer,
        /// stored in queue on suspend, cleaned up by Slot deinit on reject).
        @usableFromInline
        enum Action: ~Copyable, @unchecked Sendable {
            /// Deliver the element directly to a waiting receiver.
            case deliverToReceiver(Receive.Continuation, Element)

            /// Element was buffered successfully.
            case buffered

            /// Continuation stored, sender is now suspended.
            case suspended

            /// Channel is closed, reject the send.
            case rejectClosed

            /// Sender was already cancelled before suspension.
            case rejectCancelled
        }

        @usableFromInline
        enum Cancel: Sendable {
            case resumeWithCancellation(Send.Continuation)
            case none
        }
    }

    /// Attempt a synchronous send (non-blocking).
    ///
    /// The element is in the caller's `inout Element?`. On deliver/buffer
    /// paths it is taken from the Optional. On suspend/reject, the element
    /// remains in the Optional for the caller to handle.
    @usableFromInline
    mutating func trySend(_ element: inout Element?) -> Send.Decision {
        switch status {
        case .open:
            // If a receiver is waiting, deliver directly
            if let receiver = receiver {
                self.receiver = nil
                return .deliverToReceiver(receiver.continuation, element.take()!)
            }

            // If buffer has space, add to buffer
            if buffer.count < capacity {
                buffer.push(element.take()!, to: .back)
                return .buffered
            }

            // Buffer full — element stays in Optional for slow-path staging
            let id = nextId
            nextId &+= 1
            return .suspend(id: id)

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
    mutating func sendSuspended(
        id: UInt64,
        slot: Ownership.Slot<Element>,
        continuation: Send.Continuation
    ) -> Send.Action {
        // Check if already cancelled
        if cancelledSenders.contains(id) {
            cancelledSenders.remove(id)
            return .rejectCancelled
        }

        switch status {
        case .open:
            // Double-check: receiver might have arrived
            if let receiver = receiver {
                self.receiver = nil
                let element = slot.take(__unchecked: ())
                return .deliverToReceiver(receiver.continuation, element)
            }

            // Double-check: space might be available
            if buffer.count < capacity {
                buffer.push(slot.take(__unchecked: ()), to: .back)
                return .buffered
            }

            // Enqueue waiter — Slot reference stored in Sender
            senders.push(Sender(id: id, slot: slot, continuation: continuation), to: .back)
            return .suspended

        case .closed, .finished:
            return .rejectClosed
        }
    }

    /// Handle sender cancellation.
    ///
    /// With lazy skip, cancellation is marked but not acted upon immediately.
    /// The cancelled sender's continuation will be resumed when popped via `popNextSender`.
    @usableFromInline
    mutating func sendCancelled(id: UInt64) -> Send.Cancel {
        switch status {
        case .open:
            // Mark as cancelled - will be handled lazily on pop
            cancelledSenders.insert(id)
            return .none

        case .closed, .finished:
            // Channel is closed/finished - no senders can be waiting, don't accumulate
            return .none
        }
    }
}

// MARK: - Receive

extension Async.Channel.Bounded.State where Element: ~Copyable {
    @usableFromInline
    enum Receive {
        /// Lightweight signal carried through the continuation.
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
        /// Carries Signal (Copyable) — element travels via Ownership.Slot.
        @usableFromInline
        typealias Continuation = Async.Continuation<Signal>.Unsafe

        @usableFromInline
        enum Action: ~Copyable, @unchecked Sendable {
            /// Return the element immediately.
            /// `resumeSender`: continuation of the sender that provided this element.
            /// `cancelled`: continuations of cancelled senders skipped during pop.
            /// Nil when no cancellations occurred (the common case), avoiding
            /// a per-receive Deque heap allocation.
            case returnElement(
                Element,
                resumeSender: Send.Continuation?,
                cancelled: Deque<Send.Continuation>?
            )

            /// Receiver must suspend and wait.
            case suspend

            /// Channel is closed and drained.
            case returnNil

            /// Receiver was already cancelled before suspension.
            case rejectCancelled
        }

        @usableFromInline
        enum Cancel: Sendable {
            case resumeWithCancellation(Receive.Continuation)
            case none
        }
    }

    /// Attempt a synchronous receive (non-blocking).
    @usableFromInline
    mutating func tryReceive() -> Receive.Action {
        switch status {
        case .open:
            precondition(receiver == nil, "Single-consumer invariant violated")

            // Lazy-init: only allocate when a cancelled sender is actually found
            var cancelled: Deque<Send.Continuation>? = nil
            let collectCancelled: (Send.Continuation) -> Void = {
                if cancelled == nil { cancelled = Deque() }
                cancelled!.push($0, to: .back)
            }

            // If buffer has elements
            if let element = buffer.take(from: .front) {
                // Wake up a waiting sender if any (skipping cancelled)
                if let sender = popNextSender(resumeCancelled: collectCancelled) {
                    buffer.push(sender.slot.take(__unchecked: ()), to: .back)
                    return .returnElement(element, resumeSender: sender.continuation, cancelled: cancelled)
                }
                return .returnElement(element, resumeSender: nil, cancelled: cancelled)
            }

            // If there are waiting senders, take directly from them (skipping cancelled)
            if let sender = popNextSender(resumeCancelled: collectCancelled) {
                return .returnElement(sender.slot.take(__unchecked: ()), resumeSender: sender.continuation, cancelled: cancelled)
            }

            // Nothing available, would need to suspend
            return .suspend

        case .closed:
            if let element = buffer.take(from: .front) {
                if buffer.isEmpty {
                    status = .finished
                }
                return .returnElement(element, resumeSender: nil, cancelled: nil)
            }
            status = .finished
            return .returnNil

        case .finished:
            return .returnNil
        }
    }

    /// Register a receiver that will suspend.
    @usableFromInline
    mutating func receiveSuspended(
        continuation: Receive.Continuation
    ) -> Receive.Action {
        // Check if already cancelled
        if cancelledReceiver {
            cancelledReceiver = false
            return .rejectCancelled
        }

        switch status {
        case .open:
            precondition(receiver == nil, "Single-consumer invariant violated")

            // Lazy-init: only allocate when a cancelled sender is actually found
            var cancelled: Deque<Send.Continuation>? = nil
            let collectCancelled: (Send.Continuation) -> Void = {
                if cancelled == nil { cancelled = Deque() }
                cancelled!.push($0, to: .back)
            }

            // Double-check: element might be available
            if let element = buffer.take(from: .front) {
                if let sender = popNextSender(resumeCancelled: collectCancelled) {
                    buffer.push(sender.slot.take(__unchecked: ()), to: .back)
                    return .returnElement(element, resumeSender: sender.continuation, cancelled: cancelled)
                }
                return .returnElement(element, resumeSender: nil, cancelled: cancelled)
            }

            if let sender = popNextSender(resumeCancelled: collectCancelled) {
                return .returnElement(sender.slot.take(__unchecked: ()), resumeSender: sender.continuation, cancelled: cancelled)
            }

            // Store receiver
            receiver = Receiver(continuation: continuation)
            return .suspend

        case .closed:
            if let element = buffer.take(from: .front) {
                if buffer.isEmpty {
                    status = .finished
                }
                return .returnElement(element, resumeSender: nil, cancelled: nil)
            }
            status = .finished
            return .returnNil

        case .finished:
            return .returnNil
        }
    }

    /// Handle receiver cancellation.
    @usableFromInline
    mutating func receiveCancelled() -> Receive.Cancel {
        switch status {
        case .open:
            if let receiver = receiver {
                self.receiver = nil
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
    struct Close: Sendable {
        @usableFromInline
        let receiverToResume: Receive.Continuation?
        @usableFromInline
        var sendersToCancel: Deque<Send.Continuation>

        @usableFromInline
        init(
            receiverToResume: Receive.Continuation?,
            sendersToCancel: Deque<Send.Continuation>
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
            var sendersToCancel = Deque<Send.Continuation>()
            while let sender = senders.take(from: .front) {
                sendersToCancel.push(sender.continuation, to: .back)
            }

            // If buffer is empty and receiver is waiting, resume with nil
            if buffer.isEmpty {
                if let receiver = receiver {
                    self.receiver = nil
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
            return Close(receiverToResume: nil, sendersToCancel: Deque())
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
