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

extension Async.Channel.Unbounded {
    /// Pure state machine for unbounded channel operations.
    ///
    /// This state machine contains no side effects. All operations return
    /// `Action` values that describe what the caller should do.
    ///
    /// ## Single-Suspended-Receiver Invariant
    /// At most one task may be suspended in `receive()` at a time.
    /// Concurrent suspended receives trigger a precondition failure.
    @usableFromInline
    struct State: Sendable {
        /// Buffered elements waiting to be received.
        /// Optional to allow releasing the reference without heap allocation
        /// in `receive._modify` (set to nil instead of `= Deque()`).
        @usableFromInline
        var _buffer: Deque<Element>?

        /// Non-optional accessor for the buffer. The buffer is only nil
        /// during the brief window inside `receive._modify`; all other
        /// access is guarded by the mutex.
        @usableFromInline
        var buffer: Deque<Element> {
            _read { yield _buffer.unsafelyUnwrapped }
            _modify { yield &_buffer! }
        }

        @usableFromInline
        var slot: Slot

        /// Whether the channel has been closed.
        @usableFromInline
        var _closed: Bool

        @usableFromInline
        init() {
            self._buffer = Deque()
            self.slot = .none
            self._closed = false
        }
    }
}

// MARK: - Slot

extension Async.Channel.Unbounded.State {
    @usableFromInline
    enum Slot: Sendable {
        case none
        case wait(Receive.Continuation)
    }
}

// MARK: - Query

extension Async.Channel.Unbounded.State {
    @usableFromInline
    var closed: Bool { _closed }
}

// MARK: - Send

extension Async.Channel.Unbounded.State {
    @usableFromInline
    enum Send {
        @usableFromInline
        enum Action: Sendable {
            case give(Receive.Continuation, Element)
            case keep
            case shut
        }
    }

    /// Send an element to the channel.
    ///
    /// If a receiver is waiting, delivers directly to it.
    /// Otherwise, buffers the element.
    @usableFromInline
    mutating func send(_ element: Element) -> Send.Action {
        guard !_closed else { return .shut }

        switch slot {
        case .wait(let cont):
            slot = .none
            return .give(cont, element)
        case .none:
            buffer.back.push(element)
            return .keep
        }
    }
}

// MARK: - Receive

extension Async.Channel.Unbounded.State {
    @usableFromInline
    struct Receive {
        
        @usableFromInline
        var base: Async.Channel<Element>.Unbounded.State

        @usableFromInline
        init(_ base: Async.Channel<Element>.Unbounded.State) {
            self.base = base
        }
        
        @usableFromInline
        typealias Continuation = Async.Continuation<(Element?, Async.Channel<Element>.Error?)>.Unsafe

        @usableFromInline
        enum Step: Sendable {
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

    /// Accessor for receive operations using `_read`/`_modify` to maintain
    /// proper ownership semantics through the accessor chain.
    ///
    /// The `_modify` accessor ensures the buffer is uniquely referenced before
    /// yielding, preventing CoW corruption when nested accessors (like `Deque.take`)
    /// expect unique ownership.
    @usableFromInline
    var receive: Receive {
        _read {
            yield Receive(self)
        }
        _modify {
            // CRITICAL: Ensure buffer uniqueness BEFORE creating wrapper.
            // This must happen before copying self to maintain CoW invariant.
            // Without this, the Deque._modify accessor receives a shared reference
            // and ensureUnique() triggers a copy with corrupted capacity.
            _buffer!.reserve(.zero)

            // Transfer state to wrapper (creates copy with shared buffer reference)
            var temp = Receive(self)

            // Release self's buffer reference - temp is now the unique owner.
            // Setting to nil avoids the heap allocation that `= Deque()` incurred.
            _buffer = nil

            // Restore state from wrapper after mutation completes
            defer { self = temp.base }
            yield &temp
        }
    }
}

extension Async.Channel.Unbounded.State.Receive {
    @usableFromInline
    mutating func poll() -> Element? {
        base.buffer.front.take
    }

    @usableFromInline
    mutating func take() -> Async.Channel<Element>.Unbounded.State.Receive.Step {
        if let element = base.buffer.front.take {
            return .val(element)
        }
        if base._closed {
            return .end
        }
        return .wait
    }

    @usableFromInline
    mutating func wait(_ cont: Async.Channel<Element>.Unbounded.State.Receive.Continuation) -> Async.Channel<Element>.Unbounded.State.Receive.Step {
        precondition({
            if case .none = base.slot { return true }
            return false
        }(), "Single-suspended-receiver invariant violated")

        if let element = base.buffer.front.take {
            return .val(element)
        }
        if base._closed {
            return .end
        }

        base.slot = .wait(cont)
        return .wait
    }

    @usableFromInline
    mutating func stop() -> Async.Channel<Element>.Unbounded.State.Receive.Stop {
        switch base.slot {
        case .wait(let cont):
            base.slot = .none
            return .stop(cont)
        case .none:
            return .none
        }
    }
}

// MARK: - Close

extension Async.Channel.Unbounded.State {
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
