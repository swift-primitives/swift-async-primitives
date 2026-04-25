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

#if !hasFeature(Embedded)
import Synchronization
#endif

extension Async {
    /// An N-party synchronization primitive where all parties must arrive before any proceed.
    ///
    /// Barrier provides a rendezvous point for multiple concurrent tasks.
    /// Each task calls `arrive()` and suspends until all expected parties
    /// have arrived, at which point all are released simultaneously.
    ///
    /// ## Pattern
    /// - Create with expected party count
    /// - Each party calls `arrive()` (async, suspends until all arrive) or `arrive(_:)` (callback)
    /// - When the last party arrives, all resume together
    ///
    /// ## One-Shot Semantics
    /// A barrier can only be used once. After all parties arrive, subsequent
    /// `arrive()` calls return immediately. For reusable barriers, create
    /// a new instance.
    ///
    /// ## Cancellation
    /// `arrive()` does NOT observe Task cancellation — its non-throwing
    /// `async` signature precludes it. Two cases warrant care:
    ///
    /// 1. **Cancelled mid-await** (after `arrive()` is called, before release):
    ///    the cancelled task's continuation stays in the waiter list; when
    ///    the barrier releases (last party arrives), the cancelled task
    ///    resumes alongside the others. Cancellation is silent.
    ///
    /// 2. **Cancelled before `arrive()` is called**: the count never
    ///    increments for that party, so the barrier never reaches the
    ///    expected arrival count and **never releases**. The other parties
    ///    suspended in `arrive()` wait forever. The barrier is one-shot
    ///    by design and exposes no cancellation-release path.
    ///
    /// Callers MUST guarantee that every party calls `arrive()` exactly
    /// once. If a party may be cancelled before arrival, compose an
    /// external mechanism (e.g. a structured task group with a finally
    /// block) so the party-count contract is honored.
    ///
    /// ## Usage
    /// ```swift
    /// let barrier = Async.Barrier(parties: 3)
    ///
    /// // Three concurrent tasks (async)
    /// for i in 0..<3 {
    ///     Task {
    ///         await performPhase1(i)
    ///         await barrier.arrive()  // All wait here until 3 arrive
    ///         await performPhase2(i)  // All proceed together
    ///     }
    /// }
    ///
    /// // Or callback-based (works on embedded)
    /// barrier.arrive {
    ///     // Called when all parties have arrived
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// All operations are protected by an internal mutex.
    /// All stored properties are `let` and `Sendable` (`Mutex` provides internal synchronization).
    ///
    /// ## Embedded Swift Support
    /// On embedded platforms, use the callback-based `arrive(_:)` method.
    /// The async `arrive()` method is only available on non-embedded platforms.
    public final class Barrier: Sendable {
        private let _state: Async.Mutex<State>
        private let parties: Int

        /// Creates a new barrier expecting the given number of parties.
        ///
        /// - Parameter parties: Number of tasks that must arrive before release.
        /// - Precondition: `parties` must be at least 1.
        public init(parties: Int) {
            precondition(parties >= 1, "Barrier requires at least 1 party")
            self.parties = parties
            self._state = Async.Mutex(State())
        }
    }
}

private extension Async.Barrier {
    struct State: Sendable {
        var arrived: Int = 0
        var waiters: [Async.Continuation<Void>] = []
        var released: Bool = false
    }
}

// MARK: - Core Operations

extension Async.Barrier {
    /// Arrives at the barrier and calls the callback when all parties have arrived.
    ///
    /// If all parties have already arrived (barrier released), the callback
    /// is invoked immediately. Otherwise, the callback is stored and invoked
    /// when the last party arrives.
    ///
    /// This method works on all platforms including embedded Swift.
    ///
    /// - Parameter callback: The callback to invoke when all parties arrive.
    public func arrive(_ callback: @escaping @Sendable () -> Void) {
        // Collect waiters to resume OUTSIDE lock
        let result: (shouldResume: Bool, waitersToResume: [Async.Continuation<Void>]) = _state.withLock { state in
            // Already released - proceed immediately
            if state.released {
                return (true, [])
            }

            state.arrived += 1

            if state.arrived >= parties {
                // Last party - collect waiters for resumption outside lock
                state.released = true
                let waiters = state.waiters
                state.waiters = []
                return (true, waiters)
            } else {
                // Wait for remaining parties
                state.waiters.append(Async.Continuation(callback))
                return (false, [])
            }
        }

        // Resume waiters OUTSIDE lock (FIFO order)
        for waiter in result.waitersToResume {
            waiter.resume(returning: ())
        }

        if result.shouldResume {
            callback()
        }
    }

    /// Current count of parties that have arrived.
    public var arrived: Int {
        _state.withLock { $0.arrived }
    }

    /// Whether all parties have arrived and the barrier is released.
    public var isReleased: Bool {
        _state.withLock { $0.released }
    }
}

// MARK: - Async Arrive (Non-Embedded Only)

#if !hasFeature(Embedded)
extension Async.Barrier {
    /// Arrives at the barrier and waits for all parties.
    ///
    /// Suspends until all expected parties have arrived.
    /// When the last party arrives, all waiting parties resume.
    ///
    /// After the barrier has been released, subsequent calls return immediately.
    ///
    /// - Note: This method is only available on non-embedded platforms.
    ///   On embedded, use `arrive(_:)` instead.
    nonisolated(nonsending)
    public func arrive() async {
        await withCheckedContinuation { continuation in
            // Collect waiters to resume OUTSIDE lock
            let result: (shouldResume: Bool, waitersToResume: [Async.Continuation<Void>]) = _state.withLock { state in
                // Already released - proceed immediately
                if state.released {
                    return (true, [])
                }

                state.arrived += 1

                if state.arrived >= parties {
                    // Last party - collect waiters for resumption outside lock
                    state.released = true
                    let waiters = state.waiters
                    state.waiters = []
                    return (true, waiters)
                } else {
                    // Wait for remaining parties
                    state.waiters.append(Async.Continuation(continuation))
                    return (false, [])
                }
            }

            // Resume waiters OUTSIDE lock (FIFO order)
            for waiter in result.waitersToResume {
                waiter.resume(returning: ())
            }

            if result.shouldResume {
                continuation.resume()
            }
        }
    }
}
#endif
