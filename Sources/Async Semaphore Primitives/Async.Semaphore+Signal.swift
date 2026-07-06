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

internal import Async_Mutex_Primitives
public import Async_Primitive
public import Async_Waiter_Primitives
public import Queue_Primitive
internal import Queue_Primitives

// MARK: - Signal

extension Async.Semaphore {
    /// Result of a signal operation, computed under lock and executed outside.
    @usableFromInline
    enum SignalEffect: ~Copyable, Sendable {
        /// No waiter was waiting; permit returned to available count.
        case none

        /// An eligible waiter was found and should be resumed.
        case resume(
            Async.Waiter.Resumption,
            skipped: Async.Waiter.Queue.Drain<Async.Waiter.Resumption>
        )

        /// No eligible waiter; only skipped (flagged) waiters.
        case skippedOnly(
            Async.Waiter.Queue.Drain<Async.Waiter.Resumption>
        )
    }

    /// Releases a permit, resuming the next waiter if any.
    ///
    /// If tasks are waiting, the first waiter in FIFO order is resumed.
    /// Otherwise the available count is incremented.
    ///
    /// This method is synchronous and never suspends. It is safe to call
    /// from any context including cancellation handlers.
    public func signal() {
        let effect: SignalEffect = _state.withLock { state in
            state.metrics.releases += 1
            state.metrics.currentOutstanding -= 1

            // Try to hand off to a waiter
            var flagged = Async.Waiter.Queue.Drain<
                Async.Waiter.Queue.Flagged<Outcome, Void>
            >()
            let eligible = state.waiters.popEligible(flaggedInto: &flagged)

            // Process flagged entries
            let currentLifecycle = state.lifecycle
            var flaggedCount = 0
            var skipped = Async.Waiter.Queue.Drain<Async.Waiter.Resumption>()
            flagged.drain { flaggedEntry in
                flaggedCount += 1
                // resumption(resolving:) consumes the flagged entry in its
                // defining module — see the Flagged extension for the
                // Windows MoveOnlyChecker rationale.
                let resumption = flaggedEntry.resumption { reason in
                    let outcome: Outcome = Async.Precedence.resolve(
                        shutdown: currentLifecycle != .open,
                        cancelled: reason == .cancelled,
                        timedOut: reason == .timedOut,
                        success: .success(()),
                        onShutdown: .failure(.shutdown),
                        onCancelled: .failure(.cancelled),
                        onTimeout: .failure(.timeout)
                    )
                    // Track metrics (inside the resolve closure: Resumption
                    // is noncopyable, so the helper cannot also return the
                    // outcome)
                    switch outcome {
                    case .failure(.cancelled):
                        state.metrics.cancellations += 1

                    case .failure(.timeout):
                        state.metrics.timeouts += 1

                    default:
                        break
                    }
                    return outcome
                }

                skipped.enqueue(resumption)
            }
            state.metrics.currentWaiters -= flaggedCount

            guard let entry = eligible else {
                // No waiter, return permit to pool
                state.available += 1
                if skipped.isEmpty {
                    return .none
                }
                return .skippedOnly(skipped)
            }
            // Hand off permit to waiter
            state.metrics.currentWaiters -= 1
            state.metrics.acquisitions += 1
            state.metrics.currentOutstanding += 1
            state.metrics.peakOutstanding = max(
                state.metrics.peakOutstanding,
                state.metrics.currentOutstanding
            )
            let resumption = entry.resumption(with: .success(()))
            return .resume(resumption, skipped: skipped)
        }

        // Execute effect OUTSIDE lock
        switch consume effect {
        case .none:
            return

        case .resume(let resumption, var skipped):
            skipped.drain { $0.resume() }
            resumption.resume()

        case .skippedOnly(var skipped):
            skipped.drain { $0.resume() }
        }
    }
}

// MARK: - Metrics Accessor

extension Async.Semaphore {
    /// Returns a point-in-time snapshot of semaphore metrics.
    public var metrics: Metrics {
        _state.withLock { $0.metrics }
    }
}
