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
        /// Errors that can occur in broadcast operations.
        public enum Error: Swift.Error, Sendable, Equatable {
            /// The operation was cancelled.
            ///
            /// Thrown by `next()` when the task is cancelled while waiting.
            case cancelled
        }
    }

#endif  // !hasFeature(Embedded)
