// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025-2026 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

extension Async.Semaphore {
    /// Errors thrown by semaphore operations.
    ///
    /// Precedence order: shutdown > cancelled > timeout.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The semaphore has been shut down.
        case shutdown

        /// The waiting task was cancelled.
        case cancelled

        /// The wait operation timed out.
        case timeout
    }
}
