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

    extension Async.Channel.Unbounded.Elements {
        /// Iterator for the AsyncSequence view.
        public struct Iterator: AsyncIteratorProtocol, Sendable {
            @usableFromInline
            let storage: Async.Channel<Element>.Unbounded.Storage

            @usableFromInline
            init(storage: Async.Channel<Element>.Unbounded.Storage) {
                self.storage = storage
            }

            // swiftlint:disable:next workaround_marker_present
            // WORKAROUND: @_optimize(none) — see Unbounded.Storage.handleReceive workaround comment.
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
                case .val(let element, _):
                    return element

                case .end:
                    return nil

                case .wait:
                    break

                case .cancelled:
                    throw .cancelled
                }

                // Check cancellation before entering slow path
                if Task.isCancelled {
                    throw .cancelled
                }

                // Slow path: need to suspend
                // Element delivery uses Ownership.Slot — continuation carries Signal only.
                let signal: Async.Channel<Element>.Unbounded.State.Receive.Signal = await withTaskCancellationHandler {
                    await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Async.Channel<Element>.Unbounded.State.Receive.Signal, Never>) in
                        // Single continuation threaded through the step (see the
                        // Receiver.receive() note): stored on the wait path, handed
                        // back and resumed by handleReceive otherwise.
                        let action = storage.withLock { state in
                            state.wait(unsafe Async.Continuation.Unsafe(raw))
                        }

                        Async.Channel<Element>.Unbounded.Storage.handleReceive(consume action, storage: storage)
                    }
                } onCancel: {
                    let stopAction = storage.withLock { state in
                        state.stop()
                    }

                    switch consume stopAction {
                    case .stop(let cont):
                        cont.resume(returning: .cancelled)

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
