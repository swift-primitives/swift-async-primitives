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

public import Async_Primitive
public import Async_Lifecycle_Primitives
public import Async_Waiter_Primitives
public import Queue_Primitive

extension Async.Semaphore {
    /// Internal synchronized state for the semaphore.
    ///
    /// ~Copyable because it contains the waiter queue which is ~Copyable.
    ///
    /// `package` (not internal): the Windows 6.3.3+Asserts toolchain's
    /// MoveOnlyAddressChecker asserts
    /// `nominal->getFormalAccessScope(...).isPublicOrPackage()` when the
    /// closure in `pumpWaiters` partially mutates this noncopyable nominal
    /// under -enable-testing (MoveOnlyAddressCheckerUtils.cpp:1829).
    /// Package visibility satisfies the checker; behavior is unchanged.
    @usableFromInline
    package struct State: ~Copyable {
        /// Maximum number of concurrent permits.
        @usableFromInline
        let capacity: Int

        /// Current available permits (N). Starts at capacity.
        @usableFromInline
        var available: Int

        /// FIFO queue of suspended waiters.
        ///
        /// Uses `Async.Waiter.Queue.Unbounded` for atomic flagging and
        /// deferred resumption.
        @usableFromInline
        var waiters: Async.Waiter.Queue.Unbounded<Outcome, Void>

        /// Current lifecycle state.
        @usableFromInline
        var lifecycle: Async.Lifecycle.State

        /// Runtime metrics.
        @usableFromInline
        var metrics: Async.Semaphore.Metrics

        /// Creates state for a semaphore with the given capacity.
        @usableFromInline
        init(capacity: Int) {
            self.capacity = capacity
            self.available = capacity
            self.waiters = Async.Waiter.Queue.Unbounded()
            self.lifecycle = .open
            self.metrics = Metrics()
        }
    }
}

// MARK: - Outcome

extension Async.Semaphore {
    /// Result type for waiter resumption.
    ///
    /// Success carries Void (permit acquired). Failure carries the error.
    @usableFromInline
    typealias Outcome = Result<Void, Async.Semaphore.Error>
}
