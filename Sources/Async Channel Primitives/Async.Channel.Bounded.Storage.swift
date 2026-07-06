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

    import Synchronization
    public import Ownership_Primitives
    import Column_Primitives
    public import Buffer_Ring_Primitive
    import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive
    internal import Deque_Primitives

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// Thread-safe storage wrapping the state machine.
        ///
        /// Uses `Ownership.Mutable.Unchecked` to give the channel reference semantics
        /// while keeping a struct interface. Thread safety is provided by the
        /// wrapped `Mutex`.
        @usableFromInline
        struct Storage: Sendable {
            @usableFromInline
            let _storage: Ownership.Mutable<Async.Mutex<State>>.Unchecked

            /// Slot for transferring ~Copyable elements outside the continuation.
            ///
            /// The continuation carries a lightweight Signal; the element travels here.
            @usableFromInline
            let deliverySlot: Ownership.Slot<Element>

            @usableFromInline
            init(capacity: Index<Element>.Count) {
                self._storage = Ownership.Mutable.Unchecked(Async.Mutex(State(capacity: capacity)))
                self.deliverySlot = Ownership.Slot()
            }
        }
    }

    extension Async.Channel.Bounded.Storage where Element: ~Copyable {
        @inlinable
        func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout sending Async.Channel<Element>.Bounded.State) throws(E) -> sending T) throws(E) -> sending T {
            try _storage.mutable.value.withLock(body)
        }

        // swiftlint:disable:next workaround_marker_present
        // WORKAROUND: @_optimize(none) prevents CopyPropagation ownership
        // verification crash on ~Copyable enum consume in nested async closures.
        // WHY: CopyPropagation fails initializeConsumingUse when optimizing
        //       `switch consume` on ~Copyable enum inside withUnsafeContinuation
        //       closure inside withTaskCancellationHandler.
        // TRACKING: Not yet filed upstream.
        // WHEN TO REMOVE: When the CopyPropagation crash is fixed upstream.
        // swift-linter:disable:next optimize suppression attribute
        // REASON: deliberate crash-workaround per compiler-bug catalog §A19 ([ISSUE-008] disposition-1); remove when the SIL-optimizer fix ships.
        @_optimize(none)
        @usableFromInline
        static func handleReceive(
            _ action: consuming Async.Channel<Element>.Bounded.State.Receive.Action,
            storage: Async.Channel<Element>.Bounded.Storage
        ) {
            // The receiver continuation rides inside the action (nil on the
            // fast path, present on the slow path); it is resumed from here.
            switch consume action {
            case .returnElement(let element, let resumeSender, let cancelled, let receiver):
                if var cancelled {
                    while let c = cancelled.take(from: .front) {
                        c.resume(returning: .cancelled)
                    }
                }
                if let resumeSender { resumeSender.resume(returning: nil) }
                _ = storage.deliverySlot.store(element)
                if let receiver { receiver.resume(returning: .delivered) }

            case .returnNil(let receiver):
                if let receiver { receiver.resume(returning: .closed) }

            case .rejectCancelled(let receiver):
                if let receiver { receiver.resume(returning: .cancelled) }

            case .suspend:
                break
            }
        }

        // swiftlint:disable:next workaround_marker_present
        // WORKAROUND: Same CopyPropagation crash — see handleReceive comment.
        // swift-linter:disable:next optimize suppression attribute
        // REASON: deliberate crash-workaround per compiler-bug catalog §A19 ([ISSUE-008] disposition-1); remove when the SIL-optimizer fix ships.
        @_optimize(none)
        @usableFromInline
        static func handleSend(
            _ action: consuming Async.Channel<Element>.Bounded.State.Send.Action,
            storage: Async.Channel<Element>.Bounded.Storage
        ) {
            // The sender continuation rides inside the action (except on the
            // `.suspended` path, where it was stored in the sender queue).
            switch consume action {
            case .deliverToReceiver(let receiverCont, let element, let sender):
                _ = storage.deliverySlot.store(element)
                receiverCont.resume(returning: Async.Channel<Element>.Bounded.State.Receive.Signal.delivered)
                sender.resume(returning: nil)

            case .buffered(let sender):
                sender.resume(returning: nil)

            case .rejectClosed(let sender):
                sender.resume(returning: .closed)

            case .rejectCancelled(let sender):
                sender.resume(returning: .cancelled)

            case .suspended:
                break
            }
        }
    }

#endif  // !hasFeature(Embedded)
