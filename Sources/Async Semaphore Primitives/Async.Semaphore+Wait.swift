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

#if !hasFeature(Embedded)
    public import Async_Primitive
    internal import Async_Mutex_Primitives
    internal import Async_Waiter_Primitives
    internal import Queue_Primitive
    internal import Queue_Primitives

    // MARK: - Wait (Async)

    extension Async.Semaphore {
        /// Acquires a permit, suspending if none available.
        ///
        /// If a permit is available (N > 0), decrements and returns immediately.
        /// Otherwise suspends the calling task in FIFO order until a permit is
        /// released via `signal()`.
        ///
        /// Respects Task cancellation: throws `.cancelled` if the task is
        /// cancelled while waiting.
        ///
        /// - Throws: `Async.Semaphore.Error.shutdown` if shut down.
        /// - Throws: `Async.Semaphore.Error.cancelled` if the task is cancelled.
        nonisolated(nonsending)
            // swiftlint:disable:next prefer_self_in_static_references - reason: `Self.Error` does not compile in a throws() clause on this toolchain ('Error' is not a member type of type 'Self', verified via swiftc) — verified 2026-07-06.
            public func wait() async throws(Async.Semaphore.Error)
        {
            // Phase 1: Try immediate acquisition under lock
            enum Action {
                case acquired
                case shutdown
                case suspend
            }

            let action: Action = _state.withLock { state in
                guard state.lifecycle.isOpen else {
                    return .shutdown
                }

                if state.available > 0 {
                    state.available -= 1
                    state.metrics.acquisitions += 1
                    state.metrics.currentOutstanding += 1
                    state.metrics.peakOutstanding = max(
                        state.metrics.peakOutstanding,
                        state.metrics.currentOutstanding
                    )
                    return .acquired
                }

                return .suspend
            }

            switch action {
            case .acquired:
                return

            case .shutdown:
                throw .shutdown

            case .suspend:
                try await suspendForPermit()
            }
        }

        /// Acquires a permit with a timeout, suspending up to the given duration.
        ///
        /// - Parameter timeout: Maximum duration to wait for a permit.
        /// - Throws: `Async.Semaphore.Error.timeout` if the duration expires.
        /// - Throws: `Async.Semaphore.Error.shutdown` if shut down.
        /// - Throws: `Async.Semaphore.Error.cancelled` if the task is cancelled.
        nonisolated(nonsending)
            // swiftlint:disable:next prefer_self_in_static_references - reason: `Self.Error` does not compile in a throws() clause on this toolchain ('Error' is not a member type of type 'Self', verified via swiftc) — verified 2026-07-06.
            public func wait(timeout: Duration) async throws(Async.Semaphore.Error)
        {
            enum Action {
                case acquired
                case shutdown
                case suspend
            }

            let action: Action = _state.withLock { state in
                guard state.lifecycle.isOpen else {
                    return .shutdown
                }

                if state.available > 0 {
                    state.available -= 1
                    state.metrics.acquisitions += 1
                    state.metrics.currentOutstanding += 1
                    state.metrics.peakOutstanding = max(
                        state.metrics.peakOutstanding,
                        state.metrics.currentOutstanding
                    )
                    return .acquired
                }

                return .suspend
            }

            switch action {
            case .acquired:
                return

            case .shutdown:
                throw .shutdown

            case .suspend:
                try await suspendForPermit(timeout: timeout)
            }
        }
    }

    // MARK: - Suspension Implementation

    extension Async.Semaphore {
        /// Suspends the calling task until a permit becomes available.
        ///
        /// Uses `withTaskCancellationHandler` + flag-based cancellation,
        /// following the same pattern as Pool.Bounded.
        @usableFromInline
        // swiftlint:disable:next prefer_self_in_static_references - reason: `Self.Error` does not compile in a throws() clause on this toolchain ('Error' is not a member type of type 'Self', verified via swiftc) — verified 2026-07-06.
        func suspendForPermit() async throws(Async.Semaphore.Error) {
            let flag = Async.Waiter.Flag()

            let outcome: Outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    _state.withLock { state in
                        // Re-check under lock: lifecycle may have changed
                        // or a permit may have become available
                        if !state.lifecycle.isOpen {
                            continuation.resume(returning: .failure(.shutdown))
                            return
                        }
                        if state.available > 0 {
                            state.available -= 1
                            state.metrics.acquisitions += 1
                            state.metrics.currentOutstanding += 1
                            state.metrics.peakOutstanding = max(
                                state.metrics.peakOutstanding,
                                state.metrics.currentOutstanding
                            )
                            continuation.resume(returning: .success(()))
                            return
                        }

                        let entry = Async.Waiter.Entry<Outcome, Void>(
                            continuation: Async.Continuation(continuation),
                            flag: flag
                        )
                        state.waiters.enqueue(entry)
                        state.metrics.currentWaiters += 1
                    }
                }
            } onCancel: {
                if flag.cancel() {
                    Task { self.pumpWaiters() }
                }
            }

            switch outcome {
            case .success:
                return

            case .failure(let error):
                throw error
            }
        }

        /// Suspends with a timeout deadline.
        @usableFromInline
        // swiftlint:disable:next prefer_self_in_static_references - reason: `Self.Error` does not compile in a throws() clause on this toolchain ('Error' is not a member type of type 'Self', verified via swiftc) — verified 2026-07-06.
        func suspendForPermit(timeout: Duration) async throws(Async.Semaphore.Error) {
            let flag = Async.Waiter.Flag()

            // Start the timeout task before suspending
            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    // Cancellation (or any other Task.sleep failure) — the
                    // timeout task was cancelled (e.g. the wait completed
                    // first), so there is nothing to do.
                    return
                }
                if flag.timeout() {
                    self.pumpWaiters()
                }
            }

            let outcome: Outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    _state.withLock { state in
                        if !state.lifecycle.isOpen {
                            continuation.resume(returning: .failure(.shutdown))
                            return
                        }
                        if state.available > 0 {
                            state.available -= 1
                            state.metrics.acquisitions += 1
                            state.metrics.currentOutstanding += 1
                            state.metrics.peakOutstanding = max(
                                state.metrics.peakOutstanding,
                                state.metrics.currentOutstanding
                            )
                            continuation.resume(returning: .success(()))
                            return
                        }

                        let entry = Async.Waiter.Entry<Outcome, Void>(
                            continuation: Async.Continuation(continuation),
                            flag: flag
                        )
                        state.waiters.enqueue(entry)
                        state.metrics.currentWaiters += 1
                    }
                }
            } onCancel: {
                if flag.cancel() {
                    Task { self.pumpWaiters() }
                }
            }

            timeoutTask.cancel()

            switch outcome {
            case .success:
                return

            case .failure(let error):
                throw error
            }
        }
    }

    // MARK: - Waiter Pumping

    extension Async.Semaphore {
        /// Pumps the waiter queue, resuming flagged waiters.
        ///
        /// Called by cancellation handlers and timeout tasks after setting
        /// a waiter's flag. Reaps flagged entries and resumes them with
        /// the appropriate error outside the lock.
        @usableFromInline
        func pumpWaiters() {
            // Collect resumptions under lock, return them for execution outside
            var pending: Async.Waiter.Queue.Drain<Async.Waiter.Resumption> = _state.withLock { state in
                let currentLifecycle = state.lifecycle

                var flagged = Async.Waiter.Queue.Drain<
                    Async.Waiter.Queue.Flagged<Outcome, Void>
                >()
                state.waiters.reapFlagged(into: &flagged)

                var reapedCount = 0
                var resumptions = Async.Waiter.Queue.Drain<Async.Waiter.Resumption>()
                // A while-let dequeue rather than drain { }: the Windows
                // 6.3.3+Asserts toolchain's MoveOnlyAddressChecker asserts
                // (MoveOnlyAddressCheckerUtils.cpp:1829) checking this body
                // as a nested closure under -enable-testing; the loop form
                // avoids the closure function entirely. Semantics identical.
                while let flaggedEntry = flagged.dequeue() {
                    reapedCount += 1
                    // resumption(resolving:) consumes the flagged entry in
                    // its defining module — see the Flagged extension for the
                    // Windows MoveOnlyChecker rationale.
                    let resumption = flaggedEntry.resumption { reason in
                        // Apply precedence: shutdown > cancelled > timeout
                        let outcome: Outcome = Async.Precedence.resolve(
                            shutdown: currentLifecycle != .open,
                            cancelled: reason == .cancelled,
                            timedOut: reason == .timedOut,
                            success: .success(()),
                            onShutdown: .failure(.shutdown),
                            onCancelled: .failure(.cancelled),
                            onTimeout: .failure(.timeout)
                        )
                        // Track metrics for flagged waiters (inside the
                        // resolve closure: Resumption is noncopyable, so the
                        // helper cannot also return the outcome)
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

                    resumptions.enqueue(resumption)
                }

                state.metrics.currentWaiters -= reapedCount
                return resumptions
            }

            // Resume OUTSIDE lock
            pending.drain { $0.resume() }
        }
    }
#endif
