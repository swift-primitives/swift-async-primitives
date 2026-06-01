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
    public import Deque_Primitives

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
            var buffer: Deque<Element>

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
        @usableFromInline
        enum Slot: Sendable {
            case none
            case wait(Receive.Continuation)
            case cancelled
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
                switch self.slot {
                case .wait(let cont):
                    self.slot = .none
                    return .give(cont, element.take()!)
                case .none, .cancelled:
                    buffer.push(element.take()!, to: .back)
                    return .keep
                }
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

            @usableFromInline
            enum Step: ~Copyable {
                case val(Element)
                case end
                case wait
                case cancelled
            }

            @usableFromInline
            enum Stop: Sendable {
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
                return .val(element)
            }
            if isClosed {
                return .end
            }
            return .wait
        }

        /// Register a receiver that will suspend.
        @usableFromInline
        mutating func wait(_ cont: Receive.Continuation) -> Receive.Step {
            if case .cancelled = slot {
                slot = .none
                return .cancelled
            }

            precondition(
                {
                    if case .none = slot { return true }
                    return false
                }(),
                "Single-suspended-receiver invariant violated"
            )

            if let element = buffer.take(from: .front) {
                return .val(element)
            }
            if isClosed {
                return .end
            }

            slot = .wait(cont)
            return .wait
        }

        /// Handle receiver cancellation.
        @usableFromInline
        mutating func stop() -> Receive.Stop {
            switch slot {
            case .wait(let cont):
                slot = .none
                return .stop(cont)
            case .none:
                slot = .cancelled
                return .none
            case .cancelled:
                return .none
            }
        }
    }

    // MARK: - Close

    extension Async.Channel.Unbounded.State where Element: ~Copyable {
        @usableFromInline
        enum Close: Sendable {
            case none
            case end(Receive.Continuation)
        }

        @usableFromInline
        mutating func close() -> Close {
            guard status == .open else { return .none }

            status = .closed

            guard buffer.isEmpty else { return .none }

            switch slot {
            case .wait(let cont):
                slot = .none
                return .end(cont)
            case .none, .cancelled:
                return .none
            }
        }
    }

#endif  // !hasFeature(Embedded)
