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

// Async.Completion requires Atomic from Synchronization and is designed for
// the withCheckedContinuation + cancellation pattern. Neither is available
// on embedded Swift.
#if !hasFeature(Embedded)

public import Synchronization

extension Async {
    /// A CAS-guarded exactly-once async completion.
    ///
    /// Provides thread-safe single-resume guarantee with multiple terminal states.
    /// Useful for bridging sync/async boundaries with timeout/cancellation support.
    ///
    /// ## CAS Discipline
    /// - `start()`: pending → running
    /// - `complete(_:)`: running → completed
    /// - `timeout()`: running → timedOut
    /// - `cancel()`: pending/running → cancelled
    /// - `fail(_:)`: pending → failed
    ///
    /// Only one of these transitions wins - guaranteeing exactly-once resume.
    /// Failed transitions throw `Transition.Error.alreadyDone`.
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
    /// do {
    ///     try completion.start()
    ///     try completion.complete(42)
    /// } catch {
    ///     // Another path already completed
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

// MARK: - Transition

extension Async.Completion {
    /// State transition namespace.
    public enum Transition {
        /// Error thrown when a state transition fails.
        public enum Error: Swift.Error, Sendable {
            /// The completion has already transitioned to a terminal state.
            case alreadyDone
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
    /// Transition to running state.
    ///
    /// Transitions: pending → running
    ///
    /// - Throws: `Transition.Error.alreadyDone` if not in pending state.
    public func start() throws(Transition.Error) {
        let (exchanged, _) = state.compareExchange(
            expected: .pending,
            desired: .running,
            ordering: .acquiringAndReleasing
        )
        guard exchanged else { throw .alreadyDone }
    }

    /// Complete successfully with a value.
    ///
    /// Transitions: running → completed
    ///
    /// - Parameter value: The success value.
    /// - Throws: `Transition.Error.alreadyDone` if not in running state.
    public func complete(_ value: sending Success) throws(Transition.Error) {
        let (exchanged, _) = state.compareExchange(
            expected: .running,
            desired: .completed,
            ordering: .acquiringAndReleasing
        )
        guard exchanged else { throw .alreadyDone }
        let cont = _continuation.withLock { cont in
            let captured = cont
            cont = nil
            return captured
        }
        cont?.resume(returning: .success(value))
    }

    /// Mark as timed out.
    ///
    /// Transitions: running → timedOut
    ///
    /// - Throws: `Transition.Error.alreadyDone` if not in running state.
    public func timeout() throws(Transition.Error) {
        let (exchanged, _) = state.compareExchange(
            expected: .running,
            desired: .timedOut,
            ordering: .acquiringAndReleasing
        )
        guard exchanged else { throw .alreadyDone }
        let cont = _continuation.withLock { cont in
            let captured = cont
            cont = nil
            return captured
        }
        cont?.resume(returning: .failure(.timeout))
    }

    /// Cancel the operation.
    ///
    /// Transitions: pending → cancelled, or running → cancelled
    ///
    /// - Throws: `Transition.Error.alreadyDone` if already complete/timed out/failed.
    public func cancel() throws(Transition.Error) {
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
        guard exchanged else { throw .alreadyDone }
        let cont = _continuation.withLock { cont in
            let captured = cont
            cont = nil
            return captured
        }
        cont?.resume(returning: .failure(.cancellation))
    }

    /// Fail with a domain error.
    ///
    /// Transitions: pending → failed
    ///
    /// - Parameter error: The domain failure error.
    /// - Throws: `Transition.Error.alreadyDone` if not in pending state.
    public func fail(_ error: Failure) throws(Transition.Error) {
        // Can fail from pending only
        let (exchanged, _) = state.compareExchange(
            expected: .pending,
            desired: .failed,
            ordering: .acquiringAndReleasing
        )
        guard exchanged else { throw .alreadyDone }
        let cont = _continuation.withLock { cont in
            let captured = cont
            cont = nil
            return captured
        }
        cont?.resume(returning: .failure(.failure(error)))
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
    /// - Throws: `Transition.Error.alreadyDone` if transition fails.
    public func fail(_ error: Error) throws(Transition.Error) {
        switch error {
        case .timeout:
            try timeout()
        case .cancellation:
            try cancel()
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

#endif  // !hasFeature(Embedded)
