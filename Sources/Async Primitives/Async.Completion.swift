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

public import Synchronization

extension Async {
    /// A CAS-guarded exactly-once async completion.
    ///
    /// Provides thread-safe single-resume guarantee with multiple terminal states.
    /// Useful for bridging sync/async boundaries with timeout/cancellation support.
    ///
    /// ## CAS Discipline
    /// - `tryStart()`: pending → running
    /// - `tryComplete(_:)`: running → completed
    /// - `tryTimeout()`: running → timedOut
    /// - `tryCancel()`: pending/running → cancelled
    /// - `tryFail(_:)`: pending → failed
    ///
    /// Only one of these transitions wins - guaranteeing exactly-once resume.
    ///
    /// ## Usage
    /// ```swift
    /// let completion = Async.Completion<Int, Never>()
    ///
    /// // Async side - wait for result
    /// let result = await withCheckedContinuation { continuation in
    ///     completion.setContinuation(continuation)
    /// }
    ///
    /// // Sync side - complete (exactly one wins)
    /// if completion.tryStart() {
    ///     completion.tryComplete(42)
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// Uses `@unchecked Sendable` because internal state is protected by:
    /// - Atomic state machine for CAS transitions
    /// - Mutex for continuation storage
    public final class Completion<Success: Sendable, Failure: Error & Sendable>: @unchecked Sendable {
        /// Result type for continuation resume.
        public typealias Result = Swift.Result<Success, Error>

        /// Error type wrapping timeout, cancellation, and domain failures.
        public enum Error: Swift.Error, Sendable {
            /// Operation timed out.
            case timeout

            /// Operation was cancelled.
            case cancellation

            /// Operation failed with domain error.
            case failure(Failure)
        }

        let state: Atomic<State>
        private let _continuation: Mutex<CheckedContinuation<Result, Never>?>

        /// Creates a new completion in pending state.
        public init() {
            self.state = Atomic(.pending)
            self._continuation = Mutex(nil)
        }

        /// Atomic state for CAS discipline.
        ///
        /// ## State Machine
        /// ```
        /// pending → running → completed
        ///                   → timedOut
        ///                   → cancelled
        ///                   → failed
        /// pending → cancelled
        /// pending → failed
        /// ```
        public enum State: UInt8, AtomicRepresentable, Sendable {
            /// Initial state - not yet started.
            case pending = 0

            /// Operation is running.
            case running = 1

            /// Operation completed successfully.
            case completed = 2

            /// Operation timed out.
            case timedOut = 3

            /// Operation was cancelled.
            case cancelled = 4

            /// Operation failed with error.
            case failed = 5
        }
    }
}

// MARK: - Continuation

extension Async.Completion {
    /// Set the continuation for result delivery.
    ///
    /// Must be called exactly once before any completion method.
    /// The continuation will be resumed exactly once by whichever
    /// completion method wins the CAS race.
    ///
    /// - Parameter cont: The continuation to resume with the result.
    public func setContinuation(_ cont: CheckedContinuation<Result, Never>) {
        _continuation.withLock { $0 = cont }
    }
}

// MARK: - State Transitions

extension Async.Completion {
    /// Attempt to start running. Returns true if successful.
    ///
    /// Transitions: pending → running
    ///
    /// - Returns: `true` if transitioned to running, `false` if already in another state.
    public func tryStart() -> Bool {
        let (exchanged, _) = state.compareExchange(
            expected: .pending,
            desired: .running,
            ordering: .acquiringAndReleasing
        )
        return exchanged
    }

    /// Attempt to complete successfully. Returns true if successful.
    ///
    /// Transitions: running → completed
    ///
    /// - Parameter value: The success value.
    /// - Returns: `true` if completed successfully, `false` if not in running state.
    public func tryComplete(_ value: Success) -> Bool {
        let (exchanged, _) = state.compareExchange(
            expected: .running,
            desired: .completed,
            ordering: .acquiringAndReleasing
        )
        if exchanged {
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .success(value))
        }
        return exchanged
    }

    /// Attempt to mark as timed out. Returns true if successful.
    ///
    /// Transitions: running → timedOut
    ///
    /// - Returns: `true` if timed out successfully, `false` if not in running state.
    public func tryTimeout() -> Bool {
        let (exchanged, _) = state.compareExchange(
            expected: .running,
            desired: .timedOut,
            ordering: .acquiringAndReleasing
        )
        if exchanged {
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .failure(.timeout))
        }
        return exchanged
    }

    /// Attempt to cancel. Returns true if successful.
    ///
    /// Transitions: pending → cancelled, or running → cancelled
    ///
    /// - Returns: `true` if cancelled successfully, `false` if already complete/timed out/failed.
    public func tryCancel() -> Bool {
        // Can cancel from pending or running
        var (exchanged, original) = state.compareExchange(
            expected: .pending,
            desired: .cancelled,
            ordering: .acquiringAndReleasing
        )
        if !exchanged && original == .running {
            (exchanged, _) = state.compareExchange(
                expected: .running,
                desired: .cancelled,
                ordering: .acquiringAndReleasing
            )
        }
        if exchanged {
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .failure(.cancellation))
        }
        return exchanged
    }

    /// Attempt to fail with error. Returns true if successful.
    ///
    /// Transitions: pending → failed
    ///
    /// - Parameter error: The domain failure error.
    /// - Returns: `true` if failed successfully, `false` if not in pending state.
    public func tryFail(_ error: Failure) -> Bool {
        // Can fail from pending only
        let (exchanged, _) = state.compareExchange(
            expected: .pending,
            desired: .failed,
            ordering: .acquiringAndReleasing
        )
        if exchanged {
            let cont = _continuation.withLock { cont in
                let captured = cont
                cont = nil
                return captured
            }
            cont?.resume(returning: .failure(.failure(error)))
        }
        return exchanged
    }
}

// MARK: - Convenience for Never Failure

extension Async.Completion where Failure == Never {
    /// Fail with a non-domain error (for Never failure type).
    ///
    /// This overload is available when Failure == Never, allowing
    /// timeout and cancellation without domain errors.
    ///
    /// - Parameter error: The error (must be timeout or cancellation).
    /// - Returns: `true` if failed successfully.
    public func tryFail(_ error: Error) -> Bool {
        switch error {
        case .timeout:
            return tryTimeout()
        case .cancellation:
            return tryCancel()
        case .failure:
            // Never type - can't construct this case
            fatalError("Cannot fail with Never error type")
        }
    }
}

// MARK: - State Query

extension Async.Completion {
    /// Current state (for diagnostics).
    public var currentState: State {
        state.load(ordering: .acquiring)
    }

    /// Whether the completion is in a terminal state.
    public var isTerminal: Bool {
        switch currentState {
        case .pending, .running:
            return false
        case .completed, .timedOut, .cancelled, .failed:
            return true
        }
    }
}
