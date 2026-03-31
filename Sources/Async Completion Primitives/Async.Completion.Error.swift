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

#if !hasFeature(Embedded)

extension Async.Completion {
    /// Error type wrapping timeout, cancellation, and domain failures.
    public enum Error: Swift.Error, Sendable {
        /// Operation timed out.
        case timeout

        /// Operation was cancelled.
        case cancellation

        /// Operation failed with domain error.
        case failure(Failure)
    }
}

#endif  // !hasFeature(Embedded)
