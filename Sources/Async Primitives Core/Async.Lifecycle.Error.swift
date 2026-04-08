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
    /// Error envelope for operations on resources with lifecycle semantics.
    ///
    /// Separates lifecycle concerns (shutdown, cancellation, timeout) from
    /// operational failures. The `.failure(E)` case wraps the domain-specific
    /// error; the other cases are lifecycle infrastructure.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// func run<T>() async throws(Async.Lifecycle.Error<MyError>) -> T
    /// ```
    public enum Error<E: Swift.Error>: Swift.Error {
        /// The resource is shutting down. New operations are rejected.
        case shutdownInProgress

        /// The operation was cancelled.
        case cancellation

        /// The operation timed out.
        case timeout

        /// An operational failure.
        case failure(E)
    }
}

// MARK: - Map

extension Async.Lifecycle.Error {
    /// Maps the failure case to a different error type.
    ///
    /// Lifecycle cases (shutdown, cancellation, timeout) are preserved.
    /// Only `.failure` is transformed.
    @inlinable
    public func mapFailure<NewE: Swift.Error>(
        _ transform: (E) -> NewE
    ) -> Async.Lifecycle.Error<NewE> {
        switch self {
        case .shutdownInProgress: .shutdownInProgress
        case .cancellation: .cancellation
        case .timeout: .timeout
        case .failure(let e): .failure(transform(e))
        }
    }
}

// MARK: - Conformances

extension Async.Lifecycle.Error: Equatable where E: Equatable {}
extension Async.Lifecycle.Error: Sendable where E: Sendable {}

extension Async.Lifecycle.Error: CustomStringConvertible {
    public var description: Swift.String {
        switch self {
        case .shutdownInProgress: "shutdownInProgress"
        case .cancellation: "cancellation"
        case .timeout: "timeout"
        case .failure(let e): "failure(\(e))"
        }
    }
}
