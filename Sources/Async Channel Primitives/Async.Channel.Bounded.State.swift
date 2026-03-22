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

public import Queue_Primitives

extension Async.Channel.Bounded {
    /// Pure state machine for bounded channel operations.
    ///
    /// This state machine contains no side effects. All operations return
    /// `Action` values that describe what the caller should do.
    @usableFromInline
    struct State: Sendable {
        @usableFromInline
        var phase: Phase
        @usableFromInline
        let capacity: Int
        @usableFromInline
        var nextId: UInt64 = 0
        @usableFromInline
        var cancelledSenders: Set<UInt64> = []
        @usableFromInline
        var cancelledReceiver: Bool = false

        @usableFromInline
        init(capacity: Int) {
            self.phase = .open(
                buffer: Deque(),
                senders: Deque(),
                receiver: nil
            )
            self.capacity = capacity
        }
    }
}

// MARK: - Phase

extension Async.Channel.Bounded.State {
    @usableFromInline
    enum Phase: Sendable {
        /// Channel is open and operational.
        case open(
            buffer: Deque<Element>,
            senders: Deque<Sender>,
            receiver: Receiver?
        )

        /// Channel is closed but may still have buffered elements.
        case closed(buffer: Deque<Element>)

        /// Channel is finished - no more elements, fully drained.
        case finished

        /// Temporary state during mutation to avoid CoW.
        case modifying
    }
}

// MARK: - Sender

extension Async.Channel.Bounded.State {
    @usableFromInline
    struct Sender: Sendable {
        @usableFromInline
        let id: UInt64
        @usableFromInline
        let element: Element
        @usableFromInline
        let continuation: Send.Continuation

        @usableFromInline
        init(
            id: UInt64,
            element: Element,
            continuation: Send.Continuation
        ) {
            self.id = id
            self.element = element
            self.continuation = continuation
        }
    }
}

// MARK: - Receiver

extension Async.Channel.Bounded.State {
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

// MARK: - ID Generation

extension Async.Channel.Bounded.State {
    @usableFromInline
    mutating func generateId() -> UInt64 {
        let id = nextId
        nextId &+= 1
        return id
    }
}

// MARK: - Sender Queue Helpers

extension Async.Channel.Bounded.State {
    /// Pops the next non-cancelled sender from the deque.
    ///
    /// Cancelled senders are skipped and their continuations resumed via the closure.
    /// The cancellation marker is consumed from `cancelledSenders` on skip.
    ///
    /// - Invariant: Each sender id is unique and appears at most once in the deque.
    @usableFromInline
    mutating func popNextSender(
        from senders: inout Deque<Sender>,
        resumeCancelled: (Send.Continuation) -> Void
    ) -> Sender? {
        while let sender = unsafe senders.front.take {
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

extension Async.Channel.Bounded.State {
    @usableFromInline
    enum Send {
        /// Continuation type for send operations.
        /// Returns nil on success, Error on failure.
        @usableFromInline
        typealias Continuation = UnsafeContinuation<Async.Channel<Element>.Error?, Never>

        @usableFromInline
        enum Action: Sendable {
            /// Deliver the element directly to a waiting receiver.
            case deliverToReceiver(Receive.Continuation, Element)

            /// Element was buffered successfully.
            case buffered

            /// Sender must suspend and wait.
            case suspend(id: UInt64)

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
    @usableFromInline
    mutating func trySend(_ element: Element) -> Send.Action {
        switch phase {
        case .open(var buffer, let senders, let receiver):
            // If a receiver is waiting, deliver directly
            if let receiver = receiver {
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .deliverToReceiver(receiver.continuation, element)
            }

            // If buffer has space, add to buffer
            if buffer.count < capacity {
                phase = .modifying
                unsafe buffer.back.push(element)
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .buffered
            }

            // Buffer full, would need to suspend
            return .suspend(id: 0) // Caller should not use this id

        case .closed, .finished:
            return .rejectClosed

        case .modifying:
            preconditionFailure("Invalid state: modifying")
        }
    }

    /// Register a sender that will suspend.
    @usableFromInline
    mutating func sendSuspended(
        id: UInt64,
        element: Element,
        continuation: Send.Continuation
    ) -> Send.Action {
        // Check if already cancelled
        if cancelledSenders.contains(id) {
            cancelledSenders.remove(id)
            return .rejectCancelled
        }

        switch phase {
        case .open(var buffer, var senders, let receiver):
            // Double-check: receiver might have arrived
            if let receiver = receiver {
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .deliverToReceiver(receiver.continuation, element)
            }

            // Double-check: space might be available
            if buffer.count < capacity {
                phase = .modifying
                unsafe buffer.back.push(element)
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .buffered
            }

            // Enqueue waiter
            phase = .modifying
            unsafe senders.back.push(Sender(id: id, element: element, continuation: continuation))
            phase = .open(buffer: buffer, senders: senders, receiver: nil)
            return .suspend(id: id)

        case .closed, .finished:
            return .rejectClosed

        case .modifying:
            preconditionFailure("Invalid state: modifying")
        }
    }

    /// Handle sender cancellation.
    ///
    /// With lazy skip, cancellation is marked but not acted upon immediately.
    /// The cancelled sender's continuation will be resumed when popped via `popNextSender`.
    @usableFromInline
    mutating func sendCancelled(id: UInt64) -> Send.Cancel {
        switch phase {
        case .open, .modifying:
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

extension Async.Channel.Bounded.State {
    @usableFromInline
    enum Receive {
        /// Continuation type for receive operations.
        /// Returns (element, nil) on success, (nil, nil) on closed, (nil, error) on failure.
        @usableFromInline
        typealias Continuation = UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>

        @usableFromInline
        enum Action: Sendable {
            /// Return the element immediately.
            /// `resumeSender`: continuation of the sender that provided this element.
            /// `cancelled`: continuations of cancelled senders skipped during pop.
            case returnElement(
                Element,
                resumeSender: Send.Continuation?,
                cancelled: Deque<Send.Continuation>
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
    // on Property.View accessor chains (buffer.back.push, buffer.front.take).
    @usableFromInline
    mutating func tryReceive() -> Receive.Action {
        switch phase {
        case .open(var buffer, var senders, let receiver):
            precondition(receiver == nil, "Single-consumer invariant violated")

            // Collect cancelled continuations during pop
            var cancelled = Deque<Send.Continuation>()
            let collectCancelled: (Send.Continuation) -> Void = { unsafe cancelled.back.push($0) }

            // If buffer has elements
            if let element = unsafe buffer.front.take {
                // Wake up a waiting sender if any (skipping cancelled)
                if let sender = popNextSender(from: &senders, resumeCancelled: collectCancelled) {
                    phase = .modifying
                    unsafe buffer.back.push(sender.element)
                    phase = .open(buffer: buffer, senders: senders, receiver: nil)
                    return .returnElement(element, resumeSender: sender.continuation, cancelled: cancelled)
                }
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .returnElement(element, resumeSender: nil, cancelled: cancelled)
            }

            // If there are waiting senders, take directly from them (skipping cancelled)
            if let sender = popNextSender(from: &senders, resumeCancelled: collectCancelled) {
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .returnElement(sender.element, resumeSender: sender.continuation, cancelled: cancelled)
            }

            // Nothing available, would need to suspend
            phase = .open(buffer: buffer, senders: senders, receiver: nil)
            return .suspend

        case .closed(var buffer):
            if let element = unsafe buffer.front.take {
                if buffer.isEmpty {
                    phase = .finished
                } else {
                    phase = .closed(buffer: buffer)
                }
                return .returnElement(element, resumeSender: nil, cancelled: Deque())
            }
            phase = .finished
            return .returnNil

        case .finished:
            return .returnNil

        case .modifying:
            preconditionFailure("Invalid state: modifying")
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

        switch phase {
        case .open(var buffer, var senders, let receiver):
            precondition(receiver == nil, "Single-consumer invariant violated")

            // Collect cancelled continuations during pop
            var cancelled = Deque<Send.Continuation>()
            let collectCancelled: (Send.Continuation) -> Void = { unsafe cancelled.back.push($0) }

            // Double-check: element might be available
            if let element = unsafe buffer.front.take {
                if let sender = popNextSender(from: &senders, resumeCancelled: collectCancelled) {
                    phase = .modifying
                    unsafe buffer.back.push(sender.element)
                    phase = .open(buffer: buffer, senders: senders, receiver: nil)
                    return .returnElement(element, resumeSender: sender.continuation, cancelled: cancelled)
                }
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .returnElement(element, resumeSender: nil, cancelled: cancelled)
            }

            if let sender = popNextSender(from: &senders, resumeCancelled: collectCancelled) {
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .returnElement(sender.element, resumeSender: sender.continuation, cancelled: cancelled)
            }

            // Store receiver
            phase = .open(
                buffer: buffer,
                senders: senders,
                receiver: Receiver(continuation: continuation)
            )
            return .suspend

        case .closed(var buffer):
            if let element = unsafe buffer.front.take {
                if buffer.isEmpty {
                    phase = .finished
                } else {
                    phase = .closed(buffer: buffer)
                }
                return .returnElement(element, resumeSender: nil, cancelled: Deque())
            }
            phase = .finished
            return .returnNil

        case .finished:
            return .returnNil

        case .modifying:
            preconditionFailure("Invalid state: modifying")
        }
    }

    /// Handle receiver cancellation.
    @usableFromInline
    mutating func receiveCancelled() -> Receive.Cancel {
        switch phase {
        case .open(let buffer, let senders, let receiver):
            if let receiver = receiver {
                phase = .open(buffer: buffer, senders: senders, receiver: nil)
                return .resumeWithCancellation(receiver.continuation)
            }
            // Receiver not suspended yet - mark as cancelled
            cancelledReceiver = true
            return .none

        case .closed, .finished:
            return .none

        case .modifying:
            cancelledReceiver = true
            return .none
        }
    }
}

// MARK: - Close

extension Async.Channel.Bounded.State {
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
        switch phase {
        case .open(let buffer, var senders, let receiver):
            // Collect senders to cancel (drain the deque)
            var sendersToCancel = Deque<Send.Continuation>()
            while let sender = unsafe senders.front.take {
                unsafe sendersToCancel.back.push(sender.continuation)
            }

            // If buffer is empty and receiver is waiting, resume with nil
            if buffer.isEmpty {
                if let receiver = receiver {
                    phase = .finished
                    return Close(
                        receiverToResume: receiver.continuation,
                        sendersToCancel: sendersToCancel
                    )
                }
                phase = .finished
            } else {
                phase = .closed(buffer: buffer)
            }
            return Close(receiverToResume: nil, sendersToCancel: sendersToCancel)

        case .closed, .finished:
            return Close(receiverToResume: nil, sendersToCancel: Deque())

        case .modifying:
            preconditionFailure("Invalid state: modifying")
        }
    }
}

// MARK: - Query

extension Async.Channel.Bounded.State {
    @usableFromInline
    var isClosed: Bool {
        switch phase {
        case .open:
            return false
        case .closed, .finished:
            return true
        case .modifying:
            preconditionFailure("Invalid state: modifying")
        }
    }
}

#endif  // !hasFeature(Embedded)
