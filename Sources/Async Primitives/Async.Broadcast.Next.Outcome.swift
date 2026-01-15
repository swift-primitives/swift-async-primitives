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
    /// Namespace for next operation types.
    public enum Next {}
}

extension Async.Broadcast.Next {
    /// Outcome of a next() operation.
    enum Outcome {
        /// An element was received.
        case element(Element)
        /// The broadcast is finished and no more elements are available.
        case finished
        /// The operation was cancelled.
        case cancelled
    }
}

#endif  // !hasFeature(Embedded)
