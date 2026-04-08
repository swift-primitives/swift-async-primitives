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

public import Async_Primitives_Core
public import Async_Waiter_Primitives

extension Async.Semaphore {
    /// Internal synchronized state for the semaphore.
    ///
    /// ~Copyable because it contains the waiter queue which is ~Copyable.
    @usableFromInline
    struct State: ~Copyable {
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
