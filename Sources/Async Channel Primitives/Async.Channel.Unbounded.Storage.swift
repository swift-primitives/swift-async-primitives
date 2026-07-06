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
    import Buffer_Ring_Primitive
    import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async.Channel.Unbounded where Element: ~Copyable {
        /// Thread-safe storage wrapping the state machine.
        @usableFromInline
        final class Storage: Sendable {
            @usableFromInline
            let mutex: Async.Mutex<State>

            /// Slot for transferring ~Copyable elements outside the continuation.
            /// The continuation carries a lightweight Signal; the element travels here.
            @usableFromInline
            let deliverySlot: Ownership.Slot<Element>

            @usableFromInline
            init() {
                self.mutex = Async.Mutex(State())
                self.deliverySlot = Ownership.Slot()
            }

            deinit {
                let action = withLock { state in
                    state.close()
                }

                switch consume action {
                case .none:
                    break
                case .end(let cont):
                    cont.resume(returning: .closed)
                }
            }
        }
    }

    extension Async.Channel.Unbounded.Storage where Element: ~Copyable {
        @inlinable
        func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout sending Async.Channel<Element>.Unbounded.State) throws(E) -> sending T) throws(E) -> sending T {
            try mutex.withLock(body)
        }

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
            _ action: consuming Async.Channel<Element>.Unbounded.State.Receive.Step,
            storage: Async.Channel<Element>.Unbounded.Storage
        ) {
            // The receiver continuation rides inside the step (nil on the fast
            // path, present on the slow path); it is resumed from here. The
            // `.wait` case stored it in the slot, so nothing to resume.
            switch consume action {
            case .val(let element, let receiver):
                _ = storage.deliverySlot.store(element)
                if let receiver { receiver.resume(returning: .delivered) }
            case .end(let receiver):
                if let receiver { receiver.resume(returning: .closed) }
            case .wait:
                break
            case .cancelled(let receiver):
                if let receiver { receiver.resume(returning: .cancelled) }
            }
        }
    }

#endif  // !hasFeature(Embedded)
