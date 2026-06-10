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

    import Synchronization

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
        ///     completion.set(continuation: continuation)
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
        /// Internal state is protected by:
        /// - Atomic state machine for CAS transitions
        /// - Mutex for continuation storage
        /// All stored properties are `let` and `Sendable`.
        public final class Completion<Success: Sendable, Failure: Swift.Error>: Sendable {
            /// Result type for continuation resume.
            public typealias Result = Swift.Result<Success, Async.Completion<Success, Failure>.Error>

            private let _state: Atomic<State>
            private let _continuation: Async.Mutex<CheckedContinuation<Result, Never>?>

            /// Creates a new completion in pending state.
            public init() {
                self._state = Atomic(.pending)
                self._continuation = Async.Mutex(nil)
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
        /// - Parameter continuation: The continuation to resume with the result.
        public func set(continuation: CheckedContinuation<Result, Never>) {
            _continuation.withLock { $0 = continuation }
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
            let (exchanged, _) = _state.compareExchange(
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
            let (exchanged, _) = _state.compareExchange(
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
            let (exchanged, _) = _state.compareExchange(
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
            var (exchanged, original) = _state.compareExchange(
                expected: .pending,
                desired: .cancelled,
                ordering: .acquiringAndReleasing
            )
            if !exchanged && original == .running {
                (exchanged, _) = _state.compareExchange(
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
            cont?.resume(returning: .failure(.cancelled))
        }

        /// Fail with a domain error.
        ///
        /// Transitions: pending → failed
        ///
        /// - Parameter error: The domain failure error.
        /// - Throws: `Transition.Error.alreadyDone` if not in pending state.
        public func fail(_ error: Failure) throws(Transition.Error) {
            // Can fail from pending only
            let (exchanged, _) = _state.compareExchange(
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
        /// - Parameter error: The error (must be timeout or cancelled).
        /// - Throws: `Transition.Error.alreadyDone` if transition fails.
        public func fail(_ error: Async.Completion<Success, Never>.Error) throws(Transition.Error) {
            switch error {
            case .timeout:
                try timeout()
            case .cancelled:
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
        public var state: State {
            _state.load(ordering: .acquiring)
        }

        /// Whether the completion is in a terminal state.
        public var isTerminal: Bool {
            switch state {
            case .pending, .running:
                return false
            case .completed, .timedOut, .cancelled, .failed:
                return true
            }
        }
    }

#endif  // !hasFeature(Embedded)
