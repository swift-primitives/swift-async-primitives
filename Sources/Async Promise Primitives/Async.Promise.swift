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
    /// A single-value async primitive that can be fulfilled once and awaited many times.
    ///
    /// Promise provides a fundamental coordination pattern where one task
    /// produces a value and one or more tasks consume it. Once fulfilled,
    /// the value is available immediately to all current and future awaiters.
    ///
    /// ## Pattern
    /// - Producer calls `fulfill(_:)` (sync, delivers value)
    /// - Consumers call `value` (async, suspends until fulfilled) or `wait(_:)` (callback-based)
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
    /// // Consumer tasks (async)
    /// Task {
    ///     let config = await result.value
    ///     // Use config
    /// }
    ///
    /// // Consumer (callback-based, works on embedded)
    /// result.wait { config in
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
    /// All stored properties are `let` and `Sendable` (`Mutex` provides internal synchronization).
    ///
    /// ## Embedded Swift Support
    /// On embedded platforms, use the callback-based `wait(_:)` method.
    /// The async `value` property is only available on non-embedded platforms.
    public final class Promise<Value: Sendable>: Sendable {
        private let _state: Async.Mutex<State>

        private struct State: Sendable {
            var waiters: [Async.Continuation<Value>] = []
            var fulfilled: Value? = nil
        }

        /// Creates a new unfulfilled promise.
        public init() {
            self._state = Async.Mutex(State())
        }
    }
}

// MARK: - Core Operations

extension Async.Promise {
    /// Fulfills the promise with a value, releasing all waiting tasks.
    ///
    /// After this call:
    /// - All currently waiting tasks/callbacks resume with the value
    /// - All future `value` accesses or `wait(_:)` calls return immediately
    ///
    /// - Parameter value: The value to fulfill the promise with.
    /// - Returns: `true` if the promise was fulfilled, `false` if already fulfilled.
    @discardableResult
    public func fulfill(_ value: sending Value) -> Bool {
        let waitersToResume: [Async.Continuation<Value>]? = _state.withLock { state in
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

    /// Waits for the promise to be fulfilled, calling the callback with the value.
    ///
    /// If the promise is already fulfilled, the callback is invoked immediately.
    /// Otherwise, the callback is stored and invoked when `fulfill(_:)` is called.
    ///
    /// This method works on all platforms including embedded Swift.
    ///
    /// - Parameter callback: The callback to invoke with the fulfilled value.
    public func wait(_ callback: @escaping @Sendable (sending Value) -> Void) {
        let immediateValue: Value? = _state.withLock { state in
            if let value = state.fulfilled {
                return value
            }
            state.waiters.append(Async.Continuation(callback))
            return nil
        }
        if let value = immediateValue {
            callback(value)
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

// MARK: - Async Value Getter (Non-Embedded Only)

#if !hasFeature(Embedded)
extension Async.Promise {
    /// The promised value, suspending until fulfilled.
    ///
    /// If the promise is already fulfilled, returns the value immediately.
    /// Otherwise, suspends until another task calls `fulfill(_:)`.
    ///
    /// Multiple tasks can await concurrently - all will receive the same value.
    ///
    /// - Note: This property is only available on non-embedded platforms.
    ///   On embedded, use `wait(_:)` instead.
    nonisolated(nonsending)
    public func value() async -> Value {
        await withCheckedContinuation { continuation in
            let immediateValue: Value? = _state.withLock { state in
                if let value = state.fulfilled {
                    return value
                }
                state.waiters.append(Async.Continuation(continuation))
                return nil
            }
            if let value = immediateValue {
                continuation.resume(returning: value)
            }
        }
    }
}
#endif
