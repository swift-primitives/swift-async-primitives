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
    public import Deque_Primitives
    public import Column_Primitives
    public import Buffer_Ring_Primitive
    public import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async.Channel.Unbounded where Element: ~Copyable {
        /// Pure state machine for unbounded channel operations.
        ///
        /// This state machine contains no side effects. All operations return
        /// `Action` values that describe what the caller should do.
        ///
        /// ## Single-Suspended-Receiver Invariant
        /// At most one task may be suspended in `receive()` at a time.
        /// Concurrent suspended receives trigger a precondition failure.
        @usableFromInline
        struct State: ~Copyable {
            @usableFromInline
            var buffer: Deque<Column.Ring<Element>>

            @usableFromInline
            var slot: Slot

            @usableFromInline
            var status: Status

            @usableFromInline
            init() {
                self.buffer = Deque()
                self.slot = .none
                self.status = .open
            }
        }
    }

    // MARK: - Status

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
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

    // MARK: - Slot

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
        // `~Copyable`: `.wait` carries a `Receive.Continuation` (now `~Copyable`).
        @usableFromInline
        enum Slot: ~Copyable, Sendable {
            case none
            case wait(Receive.Continuation)
            case cancelled
        }
    }

    extension Async.Channel.Unbounded.State.Slot where Element: ~Copyable {
        /// Whether the slot is `.cancelled`. Borrows (does not consume) `self` —
        /// `if case .cancelled = slot` would consume the `~Copyable` enum.
        @usableFromInline
        var isCancelled: Bool { switch self { case .cancelled: true; default: false } }

        /// Whether the slot is `.none`. Borrowing discriminator check.
        @usableFromInline
        var isNone: Bool { switch self { case .none: true; default: false } }

        /// Moves the suspended continuation out of a `.wait` slot, resetting the
        /// slot to `.none`; `.none` and `.cancelled` are left unchanged.
        ///
        /// The `swap` is load-bearing: a `~Copyable` enum stored in a property of
        /// `self` cannot be extracted via `switch consume self.slot` because Swift
        /// forbids partially reinitializing `self` after a consume. Swapping the
        /// slot out into a local first sidesteps that restriction.
        @usableFromInline
        mutating func takeWaiter() -> Async.Channel<Element>.Unbounded.State.Receive.Continuation? {
            var taken = Self.none
            swap(&self, &taken)
            switch consume taken {
            case .wait(let cont):
                return cont
            case .none:
                return nil
            case .cancelled:
                self = .cancelled
                return nil
            }
        }
    }

    // MARK: - Query

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
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

    // MARK: - Send

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
        @usableFromInline
        enum Send {
            @usableFromInline
            enum Action: ~Copyable {
                case give(Receive.Continuation, Element)
                case keep
                case shut
            }
        }

        /// Send an element to the channel.
        ///
        /// The element is in the caller's `inout Element?`. On deliver, it is
        /// taken and returned in the action. On buffer, it is taken and pushed.
        /// On shut, it remains in the Optional (cleaned up by deinit).
        @usableFromInline
        mutating func send(_ element: inout Element?) -> Send.Action {
            switch status {
            case .open:
                if let cont = slot.takeWaiter() {
                    return .give(cont, element.take()!)
                }
                buffer.push(element.take()!, to: .back)
                return .keep
            case .closed, .finished:
                return .shut
            }
        }
    }

    // MARK: - Receive

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
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

            // `Step` is shared by the fast path `receive()` (no continuation) and
            // the slow path `wait(_:)` (has one), so the handed-back receiver
            // continuation is optional. It is resumed from `handleReceive`; the
            // `.wait` case stores the continuation in the slot instead.
            @usableFromInline
            enum Step: ~Copyable {
                case val(Element, receiver: Receive.Continuation?)
                case end(receiver: Receive.Continuation?)
                case wait
                case cancelled(receiver: Receive.Continuation?)
            }

            // `~Copyable`: `.stop` carries a `Continuation` (now `~Copyable`).
            @usableFromInline
            enum Stop: ~Copyable, Sendable {
                case none
                case stop(Continuation)
            }
        }

        /// Non-blocking receive: take from buffer if available.
        @usableFromInline
        mutating func poll() -> Element? {
            buffer.take(from: .front)
        }

        /// Synchronous receive attempt.
        @usableFromInline
        mutating func receive() -> Receive.Step {
            if let element = buffer.take(from: .front) {
                return .val(element, receiver: nil)
            }
            if isClosed {
                return .end(receiver: nil)
            }
            return .wait
        }

        /// Register a receiver that will suspend.
        @usableFromInline
        mutating func wait(_ cont: consuming Receive.Continuation) -> Receive.Step {
            if slot.isCancelled {
                slot = .none
                return .cancelled(receiver: cont)
            }

            precondition(
                slot.isNone,
                "Single-suspended-receiver invariant violated"
            )

            if let element = buffer.take(from: .front) {
                return .val(element, receiver: cont)
            }
            if isClosed {
                return .end(receiver: cont)
            }

            slot = .wait(cont)
            return .wait
        }

        /// Handle receiver cancellation.
        @usableFromInline
        mutating func stop() -> Receive.Stop {
            if let cont = slot.takeWaiter() {
                return .stop(cont)
            }
            // Slot was `.none` or `.cancelled` (takeWaiter left it unchanged);
            // either way it becomes `.cancelled` to reject a later `wait`.
            slot = .cancelled
            return .none
        }
    }

    // MARK: - Close

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
        // `~Copyable`: `.end` carries a `Receive.Continuation` (now `~Copyable`).
        @usableFromInline
        enum Close: ~Copyable, Sendable {
            case none
            case end(Receive.Continuation)
        }

        @usableFromInline
        mutating func close() -> Close {
            guard status == .open else { return .none }

            status = .closed

            guard buffer.isEmpty else { return .none }

            if let cont = slot.takeWaiter() {
                return .end(cont)
            }
            return .none
        }
    }

#endif  // !hasFeature(Embedded)
