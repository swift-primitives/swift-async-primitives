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

    extension Async.Channel.Bounded.Elements {
        /// Iterator for the AsyncSequence view.
        public struct Iterator: AsyncIteratorProtocol, Sendable {
            @usableFromInline
            let storage: Async.Channel<Element>.Bounded.Storage

            @usableFromInline
            init(storage: Async.Channel<Element>.Bounded.Storage) {
                self.storage = storage
            }

            // swiftlint:disable:next workaround_marker_present
            // WORKAROUND: @_optimize(none) — see Storage.handle workaround comment.
            // swift-linter:disable:next optimize suppression attribute
            // REASON: deliberate crash-workaround per compiler-bug catalog §A19 ([ISSUE-008] disposition-1); remove when the SIL-optimizer fix ships.
            /// Advances to the next element, suspending if the buffer is empty.
            ///
            /// - Returns: The next element, or `nil` if the channel is closed and drained.
            /// - Throws: `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
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
                case .returnElement(let element, let resumeSender, let cancelled, _):
                    if var cancelled {
                        while let c = cancelled.take(from: .front) {
                            c.resume(returning: .cancelled)
                        }
                    }
                    if let resumeSender { resumeSender.resume(returning: nil) }
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
                        // Single continuation threaded through the action (see the
                        // Receiver.receive() note): stored on the suspend path,
                        // handed back and resumed by handleReceive otherwise.
                        let action = storage.withLock { state in
                            state.suspend(continuation: unsafe Async.Continuation.Unsafe(raw))
                        }
                        Async.Channel<Element>.Bounded.Storage.handleReceive(consume action, storage: storage)
                    }
                } onCancel: {
                    let action = storage.withLock { state in
                        state.cancel()
                    }
                    switch consume action {
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
