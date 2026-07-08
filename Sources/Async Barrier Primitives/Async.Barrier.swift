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

// TODO: Re-introduce embedded support. The Shape A typed-throws cancellation
// design uses `Async.Waiter.Flag` from `Async_Waiter_Primitives`, which is
// not available on Swift Embedded. Restoring embedded compatibility requires
// either (a) splitting the callback API into an embedded-compatible file, or
// (b) reworking cancellation to use an embedded-compatible flag primitive.
// Tracked as a follow-up to the 2026-04-25 Barrier API redesign.
#if !hasFeature(Embedded)

    public import Async_Primitive
    public import Async_Lifecycle_Primitives
    internal import Async_Waiter_Primitives
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
        /// - Each party calls `arrive()` (async, suspends until all arrive) or `arrive(_:)` (callback)
        /// - When the last (non-cancelled) party arrives, all resume together
        ///
        /// ## One-Shot Semantics
        /// A barrier can only be used once. After all parties arrive, subsequent
        /// `arrive()` calls return immediately. For reusable barriers, create
        /// a new instance.
        ///
        /// ## Cancellation
        /// `arrive()` observes Task cancellation and surfaces it as
        /// ``Async/Lifecycle/Error/cancelled``. A cancelled party's intent is
        /// honored as **withdrawal from the rendezvous**: the party is removed
        /// from the waiter list and the *effective party count* decreases by
        /// one. Remaining parties release once `arrived == parties - cancelled`
        /// — the rendezvous proceeds without the cancelled party rather than
        /// deadlocking.
        ///
        /// Three behavioral cases:
        ///
        /// 1. **Cancelled mid-await** (after `arrive()` is called, before
        ///    release): `arrive()` throws ``Async/Lifecycle/Error/cancelled``.
        ///    The party's increment to `arrived` is rolled back; `cancelled`
        ///    is incremented; remaining parties' release condition is
        ///    re-evaluated.
        ///
        /// 2. **Cancelled-then-release race**: if the barrier releases
        ///    (last-party path) at approximately the same instant as
        ///    cancellation, the first signal wins. If release wins,
        ///    `arrive()` returns normally (the party arrived in time and
        ///    cancellation is silent). If cancellation wins, `arrive()`
        ///    throws `.cancelled`.
        ///
        /// 3. **Cancelled before `arrive()` is called**: the barrier never
        ///    sees this party. The waiter count is whatever the parties that
        ///    *did* call `arrive()` produced; if that's strictly less than
        ///    `parties`, the rendezvous waits forever. Callers MUST guarantee
        ///    every constructed party reaches `arrive()` (the typed-throws
        ///    contract closes only the in-flight cancellation case; the
        ///    structural "task that never reaches the call site" case
        ///    requires structured concurrency).
        ///
        /// The callback-form ``arrive(_:)`` is non-observing of cancellation
        /// by design (callbacks have no Task to cancel) and is unaffected by
        /// the typed-throws contract above.
        ///
        /// ## Usage
        /// ```swift
        /// let barrier = Async.Barrier(parties: 3)
        ///
        /// // Three concurrent tasks (async)
        /// for i in 0..<3 {
        ///     Task {
        ///         await performPhase1(i)
        ///         try await barrier.arrive()  // throws .cancelled if Task is cancelled
        ///         await performPhase2(i)      // All non-cancelled parties proceed together
        ///     }
        /// }
        ///
        /// // Or callback-based (works on embedded; non-cancellation-observing)
        /// barrier.arrive {
        ///     // Called when all (non-cancelled) parties have arrived
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

            let _state: Async.Mutex<State>

            let parties: Int

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

    extension Async.Barrier {
        /// Outcome of a suspended `arrive()` call. `.success(())` means released
        /// normally; `.failure(.cancelled)` means the party's Task was cancelled
        /// mid-await and withdrew from the rendezvous.

        typealias Outcome = Result<Void, Async.Lifecycle.Error>

        struct WaiterEntry: Sendable {
            let continuation: CheckedContinuation<Outcome, Never>
            let flag: Async.Waiter.Flag
            init(
                continuation: CheckedContinuation<Outcome, Never>,
                flag: Async.Waiter.Flag
            ) {
                self.continuation = continuation
                self.flag = flag
            }
        }

        struct State: Sendable {
            /// Count of parties that have called `arrive()` and not yet been
            /// cancelled or released.
            ///
            /// Decremented on cancellation; effectively
            /// frozen once `released` is `true`.
            var arrived: Int = 0
            /// Count of parties that arrived and were then cancelled mid-await.
            ///
            /// Reduces the effective party count: release condition is
            /// `arrived == parties - cancelled`.
            var cancelled: Int = 0
            /// Async-form pending waiters keyed by per-arrival ID.
            ///
            /// Keyed (rather
            /// than appended to a list) so cancellation can locate and remove
            /// the cancelled party's entry in O(1).
            var asyncWaiters: [UInt64: WaiterEntry] = [:]
            /// Callback-form pending waiters.
            ///
            /// Callbacks have no Task to cancel,
            /// so a flat array (FIFO) is sufficient.
            var callbackWaiters: [@Sendable () -> Void] = []
            /// Per-arrival ID counter for the async path.
            ///
            /// Monotonic; never reused.
            var nextID: UInt64 = 0
            /// Whether the rendezvous has already released.
            ///
            /// Once `true`, subsequent
            /// `arrive()` calls return immediately.
            var released: Bool = false
        }
    }

    // MARK: - Public Operations (Callback Form)

    extension Async.Barrier {
        /// Arrives at the barrier and calls the callback when all parties have arrived.
        ///
        /// If all parties have already arrived (barrier released), the callback
        /// is invoked immediately. Otherwise, the callback is stored and invoked
        /// when the last (non-cancelled) party arrives.
        ///
        /// This method works on all platforms including embedded Swift, and is
        /// non-observing of cancellation by design.
        ///
        /// - Parameter callback: The callback to invoke when all parties arrive.
        public func arrive(_ callback: @escaping @Sendable () -> Void) {
            let action: ResolveAction = _state.withLock { state in
                self.recordArrivalAndResolve(&state, callback: callback)
            }
            action.execute(immediateCallback: callback)
        }

        /// Current count of parties that have arrived (excluding cancelled).
        public var arrived: Int {
            _state.withLock { $0.arrived }
        }

        /// Count of parties that arrived and were subsequently cancelled
        /// mid-await.
        ///
        /// Effective party count for the release condition is
        /// `parties - cancelled`.
        ///
        /// This accessor is part of the public Shape A contract — consumers
        /// MAY rely on observing the cancelled-party count to reason about
        /// the effective release condition (`arrived == parties - cancelled`).
        /// It is not diagnostic-only surface.
        public var cancelledCount: Int {
            _state.withLock { $0.cancelled }
        }

        /// Whether all (non-cancelled) parties have arrived and the barrier
        /// has released.
        public var isReleased: Bool {
            _state.withLock { $0.released }
        }
    }

    // MARK: - Public Operations (Async Form, Non-Embedded)

    extension Async.Barrier {
        /// Arrives at the barrier and waits for all (non-cancelled) parties.
        ///
        /// Suspends until the rendezvous releases. Throws
        /// ``Async/Lifecycle/Error/cancelled`` if the calling Task is cancelled
        /// mid-await — the party is withdrawn from the rendezvous and remaining
        /// parties release once their reduced effective-party-count condition
        /// is met. See the type-level "Cancellation" docs for the full contract.
        ///
        /// After the barrier has been released, subsequent calls return immediately.
        ///
        /// - Throws: ``Async/Lifecycle/Error/cancelled`` if the Task is cancelled
        ///   while suspended in `arrive()`.
        ///
        /// - Note: This method is only available on non-embedded platforms.
        ///   On embedded, use ``arrive(_:)`` instead.
        nonisolated(nonsending)
            public func arrive() async throws(Async.Lifecycle.Error)
        {
            let flag = Async.Waiter.Flag()

            let outcome: Outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                    let action: SuspendAction = _state.withLock { state in
                        if state.released {
                            return .resumeImmediately(.success(()))
                        }

                        // Defensive: if the Task was already cancelled before we
                        // reached the registration site, do not register —
                        // resume immediately with .cancelled. (The cancellation
                        // handler may also fire in parallel; flag.cancel() races
                        // make either path safe.)
                        if flag.cancelled {
                            return .resumeImmediately(.failure(.cancelled))
                        }

                        state.arrived += 1
                        let needed = self.parties - state.cancelled
                        guard state.arrived >= needed else {
                            // Suspend: register self under a fresh ID.
                            let id = state.nextID
                            state.nextID += 1
                            state.asyncWaiters[id] = WaiterEntry(
                                continuation: continuation,
                                flag: flag
                            )
                            return .suspended(id: id)
                        }
                        // We are the last; release everyone and ourselves.
                        state.released = true
                        let asyncWaiters = state.asyncWaiters
                        let callbacks = state.callbackWaiters
                        state.asyncWaiters = [:]
                        state.callbackWaiters = []
                        return .release(
                            others: Array(asyncWaiters.values),
                            callbacks: callbacks,
                            mineOutcome: .success(())
                        )
                    }

                    // Side effects OUTSIDE lock.
                    switch action {
                    case .resumeImmediately(let outcome):
                        continuation.resume(returning: outcome)

                    case .release(let others, let callbacks, let mineOutcome):
                        for entry in others {
                            entry.continuation.resume(returning: .success(()))
                        }
                        for cb in callbacks {
                            cb()
                        }
                        continuation.resume(returning: mineOutcome)

                    case .suspended:
                        // Continuation stays suspended; cancellation handler or
                        // a peer's release will resume.
                        break
                    }
                }
            } onCancel: {
                // Set flag atomically; only the first writer wins.
                guard flag.cancel() else { return }

                // Find and remove our entry, decrement arrived, increment cancelled.
                // If we were already removed by a release path, this is a no-op:
                // our continuation has already been resumed with .success.
                let toResume: CheckedContinuation<Outcome, Never>? = self._state.withLock { state in
                    // Locate the entry whose flag is ours. Typically O(1) in
                    // practice (small N), and only runs once per cancellation.
                    let myID = state.asyncWaiters.first(where: { $1.flag === flag })?.key
                    guard let myID, let entry = state.asyncWaiters.removeValue(forKey: myID) else {
                        // Already removed by release; nothing to do.
                        return nil
                    }
                    state.arrived -= 1
                    state.cancelled += 1
                    return entry.continuation
                }

                toResume?.resume(returning: .failure(.cancelled))
            }

            switch outcome {
            case .success:
                return

            case .failure(let error):
                throw error
            }
        }
    }

    // MARK: - Internal helpers

    extension Async.Barrier {
        /// Action returned from a callback-form arrival's lock scope.

        enum ResolveAction: Sendable {
            /// The arrival completed the rendezvous; resume async-form peers
            /// (already done inside the lock) and run the queued callbacks
            /// plus the just-arrived callback.
            case releaseAndRun(callbacks: [@Sendable () -> Void])
            /// The rendezvous was already released before this arrival; just
            /// run the callback immediately.
            case runImmediate
            /// Suspended; nothing to do.
            case suspended
        }
    }

    extension Async.Barrier.ResolveAction {
        func execute(immediateCallback: @Sendable () -> Void) {
            switch self {
            case .releaseAndRun(let callbacks):
                for cb in callbacks { cb() }
                immediateCallback()

            case .runImmediate:
                immediateCallback()

            case .suspended:
                break
            }
        }
    }

    extension Async.Barrier {
        /// Action returned from an async-form arrival's lock scope.

        enum SuspendAction: Sendable {
            case resumeImmediately(Outcome)
            case release(others: [WaiterEntry], callbacks: [@Sendable () -> Void], mineOutcome: Outcome)
            case suspended(id: UInt64)
        }

        /// Records a callback-form arrival under the lock and returns the
        /// resolution action. Drains async waiters inline (their continuations
        /// can be resumed under the lock since `.resume(returning:)` is
        /// non-blocking and does not re-enter the barrier).

        func recordArrivalAndResolve(
            _ state: inout State,
            callback: @escaping @Sendable () -> Void
        ) -> ResolveAction {
            if state.released {
                return .runImmediate
            }

            state.arrived += 1
            let needed = parties - state.cancelled
            guard state.arrived >= needed else {
                state.callbackWaiters.append(callback)
                return .suspended
            }
            // We are the last; release everyone (async + callback peers).
            state.released = true
            let asyncWaiters = state.asyncWaiters
            let callbacks = state.callbackWaiters
            state.asyncWaiters = [:]
            state.callbackWaiters = []
            for entry in asyncWaiters.values {
                entry.continuation.resume(returning: .success(()))
            }
            return .releaseAndRun(callbacks: callbacks)
        }
    }

#endif  // !hasFeature(Embedded)
