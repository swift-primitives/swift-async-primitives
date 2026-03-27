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
    struct State: ~Copyable, @unchecked Sendable {
        @usableFromInline
        var buffer: Deque<Element>

        @usableFromInline
        var slot: Slot

        /// Whether the channel has been closed.
        @usableFromInline
        var _closed: Bool

        @usableFromInline
        init() {
            self.buffer = Deque()
            self.slot = .none
            self._closed = false
        }
    }
}

// MARK: - Slot

extension Async.Channel.Unbounded.State where Element: ~Copyable {
    @usableFromInline
    enum Slot: Sendable {
        case none
        case wait(Receive.Continuation)
    }
}

// MARK: - Query

extension Async.Channel.Unbounded.State where Element: ~Copyable {
    @usableFromInline
    var closed: Bool { _closed }
}

// MARK: - Send

extension Async.Channel.Unbounded.State where Element: ~Copyable {
    @usableFromInline
    enum Send {
        @usableFromInline
        enum Action: ~Copyable, @unchecked Sendable {
            case give(Receive.Continuation, Element)
            case keep
            case shut
        }
    }

    /// Send an element to the channel.
    ///
    /// The element is in the provided Ownership.Slot. On deliver, it is
    /// taken and returned in the action. On buffer, it is taken and pushed.
    /// On shut, it remains in the Slot (cleaned up by Slot deinit).
    @usableFromInline
    mutating func send(slot: Ownership.Slot<Element>) -> Send.Action {
        guard !_closed else { return .shut }

        switch self.slot {
        case .wait(let cont):
            self.slot = .none
            return .give(cont, slot.take(__unchecked: ()))
        case .none:
            buffer.push(slot.take(__unchecked: ()), to: .back)
            return .keep
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
        enum Step: ~Copyable, @unchecked Sendable {
            case val(Element)
            case end
            case wait
        }

        @usableFromInline
        enum Stop: Sendable {
            case none
            case stop(Continuation)
        }
    }

    /// Non-blocking receive: take from buffer if available.
    @usableFromInline
    mutating func tryReceive() -> Element? {
        buffer.take(from: .front)
    }

    /// Synchronous receive attempt.
    @usableFromInline
    mutating func receiveTake() -> Receive.Step {
        if let element = buffer.take(from: .front) {
            return .val(element)
        }
        if _closed {
            return .end
        }
        return .wait
    }

    /// Register a receiver that will suspend.
    @usableFromInline
    mutating func receiveWait(_ cont: Receive.Continuation) -> Receive.Step {
        precondition({
            if case .none = slot { return true }
            return false
        }(), "Single-suspended-receiver invariant violated")

        if let element = buffer.take(from: .front) {
            return .val(element)
        }
        if _closed {
            return .end
        }

        slot = .wait(cont)
        return .wait
    }

    /// Handle receiver cancellation.
    @usableFromInline
    mutating func receiveStop() -> Receive.Stop {
        switch slot {
        case .wait(let cont):
            slot = .none
            return .stop(cont)
        case .none:
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
        guard !_closed else { return .none }

        _closed = true

        guard buffer.isEmpty else { return .none }

        switch slot {
        case .wait(let cont):
            slot = .none
            return .end(cont)
        case .none:
            return .none
        }
    }
}

#endif  // !hasFeature(Embedded)
