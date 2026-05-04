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

    extension Async.Channel.Bounded {
        /// An AsyncSequence view over a bounded channel receiver.
        public struct Elements: AsyncSequence, Sendable {
            @usableFromInline
            let storage: Storage

            @usableFromInline
            init(storage: Storage) {
                self.storage = storage
            }
        }
    }

    extension Async.Channel.Bounded.Elements {
        public func makeAsyncIterator() -> Iterator {
            Iterator(storage: storage)
        }
    }

#endif  // !hasFeature(Embedded)
