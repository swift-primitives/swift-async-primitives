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

// Async broadcast requires task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

    import Dictionary_Primitives
    import Dictionary_Ordered_Primitives
    import Hash_Indexed_Primitive
    import Hash_Primitives
    import Column_Primitives
    import Buffer_Linear_Primitive
    import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async.Broadcast {
        /// A subscription to a broadcast channel.
        ///
        /// Conforms to `AsyncSequence` for use in `for await` loops.
        /// Each subscription maintains independent cursor position.
        public struct Subscription: Sendable {
            let broadcast: Async.Broadcast<Element>
            let id: UInt64

            init(broadcast: Async.Broadcast<Element>, id: UInt64) {
                self.broadcast = broadcast
                self.id = id
            }
        }
    }

    // MARK: - AsyncSequence

    extension Async.Broadcast.Subscription: AsyncSequence {
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(broadcast: broadcast, id: id, publication: Async.Publication<Async.Broadcast<Element>.Wait>())
        }
    }

    // MARK: - Cancel

    extension Async.Broadcast.Subscription {
        /// Unsubscribe and release resources.
        public func cancel() {
            let continuationToCancel: CheckedContinuation<Async.Broadcast<Element>.Next.Outcome, Never>? = broadcast._state.withLock { state in
                guard let subscriber = state.subscribers.removeValue(forKey: id) else { return nil }
                return subscriber.continuation
            }
            continuationToCancel?.resume(returning: .finished)
        }
    }

#endif  // !hasFeature(Embedded)
