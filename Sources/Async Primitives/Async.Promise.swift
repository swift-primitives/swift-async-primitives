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
    /// A single-value async primitive that can be fulfilled once and awaited many times.
    ///
    /// Promise provides a fundamental coordination pattern where one task
    /// produces a value and one or more tasks consume it. Once fulfilled,
    /// the value is available immediately to all current and future awaiters.
    ///
    /// ## Pattern
    /// - Producer calls `fulfill(_:)` (sync, delivers value)
    /// - Consumers call `value` (async, suspends until fulfilled)
    ///
    /// ## Single-Fulfillment Semantics
    /// A promise can only be fulfilled once. `fulfill(_:)` returns `true` on
    /// success, `false` if already fulfilled. Double-fulfillment typically
    /// indicates a logic error.
    ///
    /// ## Usage
    /// ```swift
    /// let result = Async.Promise<Config>()
    ///
    /// // Consumer tasks
    /// Task {
    ///     let config = await result.value
    ///     // Use config
    /// }
    ///
    /// // Producer task
    /// let config = await loadConfiguration()
    /// let didFulfill = result.fulfill(config)
    /// assert(didFulfill, "Promise should only be fulfilled once")
    /// ```
    ///
    /// ## Thread Safety
    /// All operations are protected by an internal mutex.
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    public final class Promise<Value: Sendable>: @unchecked Sendable {
        private let _state: Mutex<State>

        private struct State {
            var waiters: [CheckedContinuation<Value, Never>] = []
            var fulfilled: Value? = nil
        }

        /// Creates a new unfulfilled promise.
        public init() {
            self._state = Mutex(State())
        }

        /// Fulfills the promise with a value, releasing all waiting tasks.
        ///
        /// After this call:
        /// - All currently waiting tasks resume with the value
        /// - All future `value` accesses return immediately
        ///
        /// - Parameter value: The value to fulfill the promise with.
        /// - Returns: `true` if the promise was fulfilled, `false` if already fulfilled.
        @discardableResult
        public func fulfill(_ value: Value) -> Bool {
            let waitersToResume: [CheckedContinuation<Value, Never>]? = _state.withLock { state in
                guard state.fulfilled == nil else { return nil }
                state.fulfilled = value
                let waiters = state.waiters
                state.waiters = []
                return waiters
            }
            guard let waiters = waitersToResume else { return false }
            for waiter in waiters {
                waiter.resume(returning: value)
            }
            return true
        }

        /// The promised value, suspending until fulfilled.
        ///
        /// If the promise is already fulfilled, returns the value immediately.
        /// Otherwise, suspends until another task calls `fulfill(_:)`.
        ///
        /// Multiple tasks can await concurrently - all will receive the same value.
        public var value: Value {
            get async {
                await withCheckedContinuation { continuation in
                    let immediateValue: Value? = _state.withLock { state in
                        if let value = state.fulfilled {
                            return value
                        }
                        state.waiters.append(continuation)
                        return nil
                    }
                    if let value = immediateValue {
                        continuation.resume(returning: value)
                    }
                }
            }
        }

        /// Whether the promise has been fulfilled.
        public var isFulfilled: Bool {
            _state.withLock { $0.fulfilled != nil }
        }

        /// The fulfilled value, if available.
        ///
        /// Returns `nil` if the promise has not yet been fulfilled.
        /// This is a non-blocking check.
        public var fulfilledValue: Value? {
            _state.withLock { $0.fulfilled }
        }
    }
}

// MARK: - Gate (Promise<Void> specialization)

extension Async {
    /// A one-shot synchronization primitive for async coordination.
    ///
    /// Gate is a `Promise<Void>` specialized for signaling without a value.
    /// Use when you need to signal "ready" or "done" without transferring data.
    ///
    /// ## Usage
    /// ```swift
    /// let ready = Async.Gate()
    ///
    /// // Waiter
    /// await ready.wait()
    ///
    /// // Signaler
    /// ready.open()
    /// ```
    public typealias Gate = Promise<Void>
}

extension Async.Promise where Value == Void {
    /// Opens the gate, releasing all waiting tasks.
    ///
    /// Equivalent to `fulfill(())`.
    ///
    /// - Returns: `true` if the gate was opened, `false` if already open.
    @discardableResult
    public func open() -> Bool {
        fulfill(())
    }

    /// Waits until the gate is opened.
    ///
    /// Equivalent to `await value`.
    public func wait() async {
        _ = await value
    }

    /// Whether the gate is currently open.
    ///
    /// Equivalent to `isFulfilled`.
    public var isOpen: Bool {
        isFulfilled
    }
}
