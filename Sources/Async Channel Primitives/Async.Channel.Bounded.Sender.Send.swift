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
    import Buffer_Ring_Primitive
    import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async.Channel.Bounded.Sender where Element: ~Copyable {
        /// Send operation accessor with variants.
        public struct Send: Sendable {
            @usableFromInline
            let handle: Handle

            @usableFromInline
            init(handle: Handle) {
                self.handle = handle
            }

            /// Send an element without suspending.
            ///
            /// - Parameter element: The element to send.
            /// - Throws: `.full` if the buffer is full, `.closed` if the channel is closed,
            ///           `.cancelled` if the task was cancelled.
            // WORKAROUND: @_optimize(none) — see Storage.handleSend workaround comment.
            @_optimize(none)
            @inlinable
            public func immediate(_ element: consuming sending Element) throws(Async.Channel<Element>.Error) {
                let slot = Ownership.Slot(consume element)
                let decision = handle.storage.withLock { state in
                    var opt: Element? = slot.take()
                    let d = state.send(&opt)
                    if let remaining = opt.take() {
                        _ = slot.store(remaining)
                    }
                    return d
                }

                switch consume decision {
                case .deliverToReceiver(let receiverCont, let element):
                    _ = handle.storage.deliverySlot.store(element)
                    receiverCont.resume(returning: Async.Channel<Element>.Bounded.State.Receive.Signal.delivered)
                case .buffered:
                    break
                case .rejectClosed:
                    throw .closed
                case .suspend:
                    throw .full
                }
            }
        }
    }

#endif  // !hasFeature(Embedded)
