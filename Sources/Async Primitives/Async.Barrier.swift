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

import Synchronization

extension Async {
    /// An N-party synchronization primitive where all parties must arrive before any proceed.
    ///
    /// Barrier provides a rendezvous point for multiple concurrent tasks.
    /// Each task calls `arrive()` and suspends until all expected parties
    /// have arrived, at which point all are released simultaneously.
    ///
    /// ## Pattern
    /// - Create with expected party count
    /// - Each party calls `arrive()` (async, suspends until all arrive)
    /// - When the last party arrives, all resume together
    ///
    /// ## One-Shot Semantics
    /// A barrier can only be used once. After all parties arrive, subsequent
    /// `arrive()` calls return immediately. For reusable barriers, create
    /// a new instance.
    ///
    /// ## Usage
    /// ```swift
    /// let barrier = Async.Barrier(parties: 3)
    ///
    /// // Three concurrent tasks
    /// for i in 0..<3 {
    ///     Task {
    ///         await performPhase1(i)
    ///         await barrier.arrive()  // All wait here until 3 arrive
    ///         await performPhase2(i)  // All proceed together
    ///     }
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// All operations are protected by an internal mutex.
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    public final class Barrier: @unchecked Sendable {
        private let _state: Mutex<State>
        private let parties: Int

        private struct State {
            var arrived: Int = 0
            var waiters: [CheckedContinuation<Void, Never>] = []
            var released: Bool = false
        }

        /// Creates a new barrier expecting the given number of parties.
        ///
        /// - Parameter parties: Number of tasks that must arrive before release.
        /// - Precondition: `parties` must be at least 1.
        public init(parties: Int) {
            precondition(parties >= 1, "Barrier requires at least 1 party")
            self.parties = parties
            self._state = Mutex(State())
        }

        /// Arrives at the barrier and waits for all parties.
        ///
        /// Suspends until all expected parties have arrived.
        /// When the last party arrives, all waiting parties resume.
        ///
        /// After the barrier has been released, subsequent calls return immediately.
        public func arrive() async {
            await withCheckedContinuation { continuation in
                // Collect waiters to resume OUTSIDE lock
                let result: (shouldResume: Bool, waitersToResume: [CheckedContinuation<Void, Never>]) = _state.withLock { state in
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
                        state.waiters.append(continuation)
                        return (false, [])
                    }
                }

                // Resume waiters OUTSIDE lock (FIFO order)
                for waiter in result.waitersToResume {
                    waiter.resume()
                }

                if result.shouldResume {
                    continuation.resume()
                }
            }
        }

        /// Current count of parties that have arrived.
        public var arrivedCount: Int {
            _state.withLock { $0.arrived }
        }

        /// Whether all parties have arrived and the barrier is released.
        public var isReleased: Bool {
            _state.withLock { $0.released }
        }
    }
}
