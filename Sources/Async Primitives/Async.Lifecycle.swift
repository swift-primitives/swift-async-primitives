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
    /// Namespace for lifecycle management primitives.
    ///
    /// Provides building blocks for implementing graceful shutdown:
    /// - `Lifecycle.State`: Three-state machine (open → closing → closed)
    ///
    /// This is a pure state machine with no built-in waiting or synchronization.
    /// Consumers embed `State` in their own synchronized state and call
    /// the mutating methods under their own lock.
    public enum Lifecycle {}
}

// MARK: - State

extension Async.Lifecycle {
    /// Three-state lifecycle for graceful shutdown.
    ///
    /// ## States
    ///
    /// - `open`: Normal operation
    /// - `closing`: Draining existing work
    /// - `closed`: Fully shut down
    ///
    /// ## Thread Safety
    ///
    /// This is a pure value type with no built-in synchronization.
    /// Consumers must embed `State` in their own `Mutex`-protected state
    /// and call mutating methods while holding the lock.
    ///
    /// ## Usage Pattern
    ///
    /// ```swift
    /// struct MyResourceState {
    ///     var lifecycle: Async.Lifecycle.State = .open
    ///     var activeCount: Int = 0
    /// }
    ///
    /// let state = Mutex(MyResourceState())
    ///
    /// // Begin shutdown:
    /// let didBegin = state.withLock { $0.lifecycle.beginShutdown() }
    ///
    /// // Complete shutdown when drained:
    /// state.withLock { state in
    ///     if state.activeCount == 0 {
    ///         state.lifecycle.completeShutdown()
    ///     }
    /// }
    /// ```
    public enum State: Sendable, Equatable {
        /// Normal operation.
        case open

        /// Draining existing work.
        case closing

        /// Fully shut down.
        case closed
    }
}

// MARK: - State Queries

extension Async.Lifecycle.State {
    /// Whether the lifecycle is in the `open` state.
    @inlinable
    public var isOpen: Bool {
        self == .open
    }

    /// Whether the lifecycle is shutting down.
    ///
    /// Returns `true` when in `closing` or `closed` state.
    @inlinable
    public var isShuttingDown: Bool {
        self != .open
    }

    /// Whether shutdown is complete.
    ///
    /// Returns `true` only when in the `closed` state.
    @inlinable
    public var isShutdownComplete: Bool {
        self == .closed
    }
}

// MARK: - State Transitions

extension Async.Lifecycle.State {
    /// Transitions from `open` to `closing`.
    ///
    /// Idempotent: calling on `closing` or `closed` returns `false`
    /// and has no effect.
    ///
    /// ## Locking Contract
    ///
    /// Must be called under lock. The return value indicates whether
    /// the transition occurred, allowing the caller to take action
    /// (e.g., reject pending waiters) while still holding the lock.
    ///
    /// - Returns: `true` if transitioned from `open` to `closing`;
    ///            `false` if already shutting down.
    @discardableResult
    @inlinable
    public mutating func beginShutdown() -> Bool {
        guard self == .open else { return false }
        self = .closing
        return true
    }

    /// Transitions from `closing` to `closed`.
    ///
    /// Idempotent: calling on `open` or `closed` returns `false`
    /// and has no effect.
    ///
    /// ## Locking Contract
    ///
    /// Must be called under lock. The return value indicates whether
    /// the transition occurred, allowing the caller to signal
    /// shutdown-complete waiters while still holding the lock.
    ///
    /// - Returns: `true` if transitioned from `closing` to `closed`;
    ///            `false` if not in `closing` state.
    @discardableResult
    @inlinable
    public mutating func completeShutdown() -> Bool {
        guard self == .closing else { return false }
        self = .closed
        return true
    }
}
