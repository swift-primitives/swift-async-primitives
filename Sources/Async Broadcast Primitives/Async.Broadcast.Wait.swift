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

    extension Async.Broadcast {
        /// Wait token namespace for subscriber cancellation matching.
        struct Wait {
            /// Monotonically increasing token per subscriber.
            ///
            /// Incremented each time the subscriber suspends.
            /// Used to match cancellation requests to active waits.
            var token: UInt64 = 0
        }
    }

#endif  // !hasFeature(Embedded)
