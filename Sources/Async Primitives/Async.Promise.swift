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
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    ///
    /// ## Embedded Swift Support
    /// On embedded platforms, use the callback-based `wait(_:)` method.
    /// The async `value` property is only available on non-embedded platforms.
    public final class Promise<Value: Sendable>: @unchecked Sendable {
        private let _state: Async.Mutex<State>

        private struct State: Sendable {
            var waiters: [Async.Continuation<Value>] = []
            var fulfilled: Value? = nil
        }

        /// Creates a new unfulfilled promise.
        public init() {
            self._state = Async.Mutex(State())
        }

        /// Fulfills the promise with a value, releasing all waiting tasks.
        ///
        /// After this call:
        /// - All currently waiting tasks/callbacks resume with the value
        /// - All future `value` accesses or `wait(_:)` calls return immediately
        ///
        /// - Parameter value: The value to fulfill the promise with.
        /// - Returns: `true` if the promise was fulfilled, `false` if already fulfilled.
        @discardableResult
        public func fulfill(_ value: Value) -> Bool {
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
        public func wait(_ callback: @escaping @Sendable (Value) -> Void) {
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
    public var value: Value {
        get async {
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
}
#endif

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
    /// // Waiter (async, non-embedded only)
    /// await ready.wait()
    ///
    /// // Waiter (callback, works everywhere)
    /// ready.wait { }
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

    /// Waits until the gate is opened (callback-based).
    ///
    /// If the gate is already open, the callback is invoked immediately.
    /// Otherwise, the callback is stored and invoked when `open()` is called.
    ///
    /// This method works on all platforms including embedded Swift.
    ///
    /// - Parameter callback: The callback to invoke when the gate opens.
    public func wait(_ callback: @escaping @Sendable () -> Void) {
        (self as Async.Promise<Void>).wait { _ in callback() }
    }

    /// Whether the gate is currently open.
    ///
    /// Equivalent to `isFulfilled`.
    public var isOpen: Bool {
        isFulfilled
    }
}

// MARK: - Async Gate Wait (Non-Embedded Only)

#if !hasFeature(Embedded)
extension Async.Promise where Value == Void {
    /// Waits until the gate is opened (async).
    ///
    /// Equivalent to `await value`.
    ///
    /// - Note: This method is only available on non-embedded platforms.
    ///   On embedded, use `wait(_:)` instead.
    public func wait() async {
        _ = await value
    }
}
#endif
