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

extension Async {
    /// Namespace for error precedence resolution.
    ///
    /// Provides policy wiring for resolving competing error conditions
    /// into a single outcome. Standard precedence order:
    ///
    /// 1. **shutdown** dominates all
    /// 2. **cancellation** dominates timeout and success
    /// 3. **timeout** dominates success
    /// 4. **success** as fallback
    ///
    /// This is pure policy wiring with no error types defined.
    /// Consumers provide their own outcome values via closures.
    public enum Precedence {}
}

// MARK: - Resolution

extension Async.Precedence {
    /// Resolves competing conditions into a single outcome using standard precedence.
    ///
    /// ## Precedence Order
    ///
    /// 1. `shutdown` dominates all
    /// 2. `cancelled` dominates timeout and success
    /// 3. `timedOut` dominates success
    /// 4. `success` as fallback
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let outcome = Async.Precedence.resolve(
    ///     shutdown: lifecycle.shutdown.isActive,
    ///     cancelled: flag.cancelled,
    ///     timedOut: flag.timedOut,
    ///     success: .success(resource),
    ///     onShutdown: .failure(.shutdown),
    ///     onCancelled: .failure(.cancelled),
    ///     onTimeout: .failure(.timeout)
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - shutdown: Whether shutdown has been initiated.
    ///   - cancelled: Whether the operation was cancelled.
    ///   - timedOut: Whether the operation timed out.
    ///   - success: Outcome to return if no error conditions are set.
    ///   - onShutdown: Outcome to return if shutdown is set.
    ///   - onCancelled: Outcome to return if cancelled is set (and not shutdown).
    ///   - onTimeout: Outcome to return if timed out is set (and not shutdown/cancelled).
    /// - Returns: The resolved outcome.
    @inlinable
    public static func resolve<Outcome>(
        shutdown: Bool,
        cancelled: Bool,
        timedOut: Bool,
        success: @autoclosure () -> Outcome,
        onShutdown: @autoclosure () -> Outcome,
        onCancelled: @autoclosure () -> Outcome,
        onTimeout: @autoclosure () -> Outcome
    ) -> Outcome {
        if shutdown { return onShutdown() }
        if cancelled { return onCancelled() }
        if timedOut { return onTimeout() }
        return success()
    }
}
