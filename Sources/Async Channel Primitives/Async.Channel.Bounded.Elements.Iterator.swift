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

    extension Async.Channel.Bounded.Elements {
        /// Iterator for the AsyncSequence view.
        public struct Iterator: AsyncIteratorProtocol, Sendable {
            @usableFromInline
            let storage: Async.Channel<Element>.Bounded.Storage

            @usableFromInline
            init(storage: Async.Channel<Element>.Bounded.Storage) {
                self.storage = storage
            }

            // WORKAROUND: @_optimize(none) — see Storage.handle workaround comment.
            @_optimize(none)
            @inlinable
            nonisolated(nonsending)
                public mutating func next() async throws(Async.Channel<Element>.Error) -> Element?
            {
                // Capture storage to avoid capturing self in @Sendable closure
                let storage = self.storage

                // Fast path: try immediate receive
                let fastAction = storage.withLock { state in
                    state.receive()
                }

                switch consume fastAction {
                case .returnElement(let element, let resumeSender, let cancelled):
                    if var cancelled {
                        while let c = cancelled.take(from: .front) {
                            c.resume(returning: .cancelled)
                        }
                    }
                    resumeSender?.resume(returning: nil)
                    return element
                case .returnNil:
                    return nil
                case .rejectCancelled:
                    throw .cancelled
                case .suspend:
                    break
                }

                // Slow path: need to suspend
                let signal: Async.Channel<Element>.Bounded.State.Receive.Signal = await withTaskCancellationHandler {
                    await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Bounded.State.Receive.Signal, Never>) in
                        let continuation = unsafe Async.Continuation.Unsafe(raw)
                        let action = storage.withLock { state in
                            state.suspend(continuation: continuation)
                        }
                        Async.Channel<Element>.Bounded.Storage.handleReceive(consume action, storage: storage, continuation: continuation)
                    }
                } onCancel: {
                    let action = storage.withLock { state in
                        state.cancel()
                    }
                    switch action {
                    case .resumeWithCancellation(let continuation):
                        continuation.resume(returning: .cancelled)
                    case .none:
                        break
                    }
                }

                switch signal {
                case .delivered: return storage.deliverySlot.take()
                case .closed: return nil
                case .cancelled: throw .cancelled
                }
            }
        }
    }

#endif  // !hasFeature(Embedded)
