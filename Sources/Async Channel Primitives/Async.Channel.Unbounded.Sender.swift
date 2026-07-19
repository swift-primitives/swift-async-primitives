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
    import Column_Primitives
    public import Buffer_Ring_Primitive
    public import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive
    public import Deque_Primitives
    public import Pair_Primitives

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
        // swiftlint:disable:next workaround_marker_present
        // WORKAROUND: @_optimize(none) — see Unbounded.Storage.handleReceive workaround comment.
        // swift-linter:disable:next optimize suppression attribute
        // REASON: deliberate crash-workaround per compiler-bug catalog §A19 ([ISSUE-008] disposition-1); remove when the SIL-optimizer fix ships.
        /// Send an element to the channel.
        ///
        /// If a receiver is waiting, delivers the element directly.
        /// Otherwise, buffers the element for later consumption.
        ///
        /// This operation is synchronous and never suspends.
        ///
        /// - Parameter element: The element to send.
        /// - Throws: `Async.Channel<Element>.Error.closed` if the channel is closed.
        @_optimize(none)
        @inlinable
        public func send(_ element: consuming sending Element) throws(Async.Channel<Element>.Error) {
            let slot = Ownership.Slot(consume element)
            let action = storage.withLock { state in
                var opt: Element? = slot.take()
                let a = state.send(&opt)
                if let remaining = opt.take() {
                    _ = slot.store(remaining)
                }
                return a
            }

            switch consume action {
            case .give(let cont, let element):
                _ = storage.deliverySlot.store(element)
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
        public func send<S: Swift.Sequence>(contentsOf elements: sending S) throws(Async.Channel<Element>.Error) where S.Element == Element {
            let elementSlot = Ownership.Slot(Array(elements))
            let deliverySlot = storage.deliverySlot
            // A tuple cannot hold the now-`~Copyable` continuation, so `Pair`
            // (which is `~Copyable` when a component is) stands in for
            // `(cont:closed:)`: `.first` = continuation, `.second` = closed.
            var outcome = storage.withLock { state -> Pair<Async.Channel<Element>.Unbounded.State.Receive.Continuation?, Bool> in
                guard let batch = elementSlot.take() else { return Pair(nil, false) }
                var receiverCont: Async.Channel<Element>.Unbounded.State.Receive.Continuation? = nil
                var delivered = false
                for element in batch {
                    guard !state.isClosed else { return Pair(receiverCont, true) }
                    if !delivered, let cont = state.waiter.take() {
                        // `store` is `sending` (ownership-primitives e94d7c9)
                        // and RegionIsolation cannot split one element's
                        // region out of `batch` (later iterations still use
                        // it), so the loop copy cannot be sent directly.
                        // Stage it through an Optional and extract via
                        // `take()`, whose `sending` return hands back a
                        // disconnected value — the same shape `State.send`'s
                        // `element.take()` path uses one function above. The
                        // hand-off is sound: this iteration's element goes to
                        // exactly one receiver via the delivery slot and is
                        // never buffer-pushed; remaining `batch` uses touch
                        // only other elements.
                        var staged: Element? = element
                        guard let handoff = staged.take() else {
                            preconditionFailure("Async.Channel.Unbounded.Sender.send(contentsOf:): staged element vanished")
                        }
                        _ = deliverySlot.store(handoff)
                        receiverCont = consume cont
                        delivered = true
                    } else {
                        state.buffer.push(element, to: .back)
                    }
                }
                return Pair(receiverCont, false)
            }

            if let cont = outcome.first.take() {
                cont.resume(returning: Async.Channel<Element>.Unbounded.State.Receive.Signal.delivered)
            }
            if outcome.second { throw .closed }
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

            switch consume action {
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
            storage.withLock { $0.isClosed }
        }
    }

#endif  // !hasFeature(Embedded)
