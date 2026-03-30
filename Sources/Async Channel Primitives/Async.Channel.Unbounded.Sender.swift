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

extension Async.Channel.Unbounded where Element: ~Copyable {
    /// A sender view for an unbounded channel.
    ///
    /// `Sender` is a Copyable, Sendable struct that allows sending elements
    /// to an unbounded channel. Multiple senders can share the same channel
    /// by copying the view (each copy shares the underlying storage).
    ///
    /// Dropping a `Sender` has no lifecycle effect. The channel remains open
    /// until explicitly closed or until the underlying storage is released.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Unbounded()
    ///
    /// // Send elements (synchronous, throws if closed)
    /// try channel.sender.send(42)
    ///
    /// // Copy sender for another producer
    /// let sender2 = channel.sender
    /// try sender2.send(43)
    ///
    /// // Close explicitly
    /// channel.close()
    /// ```
    ///
    /// ## Thread Safety
    /// `Sender` is `Sendable` and can be shared across tasks/actors.
    public struct Sender: Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }
    }
}

// MARK: - Send Operations

extension Async.Channel.Unbounded.Sender where Element: ~Copyable {
    /// Send an element to the channel.
    ///
    /// If a receiver is waiting, delivers the element directly.
    /// Otherwise, buffers the element for later consumption.
    ///
    /// This operation is synchronous and never suspends.
    ///
    /// - Parameter element: The element to send.
    /// - Throws: `Async.Channel<Element>.Error.closed` if the channel is closed.
    @inlinable
    public func send(_ element: consuming sending Element) throws(Async.Channel<Element>.Error) {
        let slot = Ownership.Slot(consume element)
        let action = storage.withLock { state in
            var opt: Element? = slot.take()
            let a = state.send(&opt)
            if let remaining = opt.take() {
                slot.store(remaining)
            }
            return a
        }

        switch consume action {
        case .give(let cont, let element):
            storage.deliverySlot.store(element)
            cont.resume(returning: Async.Channel<Element>.Unbounded.State.Receive.Signal.delivered)
        case .keep:
            break
        case .shut:
            throw .closed
        }
    }

    /// Send multiple elements to the channel.
    ///
    /// All elements are processed under a single lock acquisition.
    /// If a receiver is waiting, the first element is delivered directly
    /// and the rest are buffered.
    ///
    /// - Parameter elements: The elements to send.
    /// - Throws: `Async.Channel<Element>.Error.closed` if the channel is closed.
    @inlinable
    public func send<S: Swift.Sequence>(contentsOf elements: S) throws(Async.Channel<Element>.Error) where S.Element == Element, Element: Sendable {
        let action: (receiver: (Async.Channel<Element>.Unbounded.State.Receive.Continuation, Element)?, closed: Bool) = storage.withLock { state in
            var firstReceiver: (Async.Channel<Element>.Unbounded.State.Receive.Continuation, Element)? = nil
            for element in elements {
                guard !state._closed else { return (firstReceiver, true) }
                switch state.slot {
                case .wait(let cont) where firstReceiver == nil:
                    state.slot = .none
                    firstReceiver = (cont, element)
                case .wait, .none, .cancelled:
                    state.buffer.back.push(element)
                }
            }
            return (firstReceiver, false)
        }

        if let (cont, element) = action.receiver {
            storage.deliverySlot.store(element)
            cont.resume(returning: Async.Channel<Element>.Unbounded.State.Receive.Signal.delivered)
        }
        if action.closed { throw .closed }
    }
}

// MARK: - Lifecycle

extension Async.Channel.Unbounded.Sender where Element: ~Copyable {
    /// Close the channel, signaling no more elements will be sent.
    ///
    /// After this call:
    /// - Any pending `receive()` returns `nil` (if buffer empty)
    /// - Future `receive()` calls drain buffer then return `nil`
    /// - Future `send()` calls throw `Error.closed`
    public func close() {
        let action = storage.withLock { state in
            state.close()
        }

        switch action {
        case .none:
            break
        case .end(let cont):
            cont.resume(returning: .closed)
        }

    }

    /// Whether the channel has been closed.
    ///
    /// Returns true when no further elements can be enqueued.
    /// This is monotonic (once true, stays true).
    ///
    /// Note: Even when `true`, `receive()` may still return elements
    /// if the buffer is not yet drained.
    public var closed: Bool {
        storage.withLock { $0.closed }
    }
}

#endif  // !hasFeature(Embedded)
