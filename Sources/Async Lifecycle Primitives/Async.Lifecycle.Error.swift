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

extension Async.Lifecycle {
    /// Canonical lifecycle-error envelope for async primitives.
    ///
    /// Represents the three lifecycle-driven failure modes shared across
    /// resources with cancellation, shutdown, and timeout semantics.
    /// Composition with body / domain errors moves into
    /// `Either<Async.Lifecycle.Error, E>` at the API surface.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// func wait() async throws(Async.Lifecycle.Error) -> Void
    /// ```
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The resource is shutting down. New operations are rejected.
        case shutdown

        /// The operation was cancelled.
        case cancelled

        /// The operation timed out.
        case timeout
    }
}

// MARK: - Conformances

extension Async.Lifecycle.Error: CustomStringConvertible {
    public var description: Swift.String {
        switch self {
        case .shutdown: "shutdown"
        case .cancelled: "cancelled"
        case .timeout: "timeout"
        }
    }
}
