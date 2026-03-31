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

extension Async.Waiter.Flag {
    /// Reason a waiter was flagged for early termination.
    ///
    /// This represents flag-level precedence only (cancelled > timedOut).
    /// Global lifecycle precedence (shutdown > cancellation > timeout > success)
    /// remains the caller's responsibility.
    public enum Reason: Sendable {
        /// The task was cancelled.
        case cancelled
        /// The operation timed out.
        case timedOut
    }

    /// Returns the reason this flag is set, if any.
    ///
    /// Checks flag bits in precedence order: cancelled > timedOut.
    /// This is flag-level precedence only; global lifecycle precedence
    /// (shutdown > cancellation > timeout > success) is the caller's responsibility.
    public var reason: Reason? {
        if cancelled { return .cancelled }
        if timedOut { return .timedOut }
        return nil
    }
}
