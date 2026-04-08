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
internal import Async_Mutex_Primitives
internal import Async_Waiter_Primitives
internal import Async_Promise_Primitives

// MARK: - Shutdown

extension Async.Semaphore {
    /// Initiates shutdown, waking all waiters with `.shutdown` error.
    ///
    /// After calling this:
    /// - All currently suspended waiters are resumed with `.shutdown`.
    /// - Future `wait()` calls throw `.shutdown` immediately.
    /// - `signal()` calls remain safe (no-op on metrics).
    ///
    /// Shutdown is idempotent: calling it multiple times is harmless.
    public func shutdown() {
        let resumptions: Async.Waiter.Queue.Drain<Async.Waiter.Resumption> = _state.withLock { state in
            // Begin shutdown (idempotent)
            guard state.lifecycle.shutdown.begin() else {
                return Async.Waiter.Queue.Drain<Async.Waiter.Resumption>()
            }

            // Drain all waiters with shutdown error
            var pending = Async.Waiter.Queue.Drain<Async.Waiter.Resumption>()
            state.waiters.drain { entry in
                pending.enqueue(entry.resumption(with: .failure(.shutdown)))
            }
            state.metrics.currentWaiters = 0

            // Complete lifecycle immediately (semaphore has no outstanding
            // resources to wait for — unlike Pool.Bounded).
            _ = state.lifecycle.shutdown.complete()

            return pending
        }

        // Resume all waiters OUTSIDE lock
        var toResume = resumptions
        toResume.drain { $0.resume() }

        // Open the shutdown gate
        _ = _shutdownGate.open()
    }

    /// Whether the semaphore has been shut down.
    public var isShutdown: Bool {
        _state.withLock { !$0.lifecycle.isOpen }
    }
}
