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

    import Index_Primitives

    extension Async.Broadcast {
        /// Buffer configuration namespace.
        struct Buffer {
            /// Maximum number of (index, element) entries retained for replay.
            let limit: Index<(index: UInt64, element: Element)>.Count
        }
    }

#endif  // !hasFeature(Embedded)
