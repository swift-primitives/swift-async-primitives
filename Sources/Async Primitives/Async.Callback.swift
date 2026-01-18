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

extension Async {
    /// A callback-based deferred value computation.
    ///
    /// `Callback` wraps a computation that produces a value asynchronously
    /// via a callback. This provides a lightweight, Foundation-free alternative
    /// to Combine publishers for single-value async operations.
    ///
    /// ## Creating Callbacks
    ///
    /// For immediate values:
    /// ```swift
    /// let callback = Async.Callback(value: "Hello")
    /// ```
    ///
    /// For deferred computation:
    /// ```swift
    /// let callback = Async.Callback<String> { done in
    ///     // Perform async work...
    ///     done("Result")
    /// }
    /// ```
    ///
    /// ## Running the Computation
    ///
    /// Execute with a callback:
    /// ```swift
    /// callback.run { value in
    ///     print("Got: \(value)")
    /// }
    /// ```
    ///
    /// Or await using Swift concurrency:
    /// ```swift
    /// let value = await callback.value
    /// ```
    ///
    /// ## Transforming Values
    ///
    /// Use ``map(_:)`` to transform the result:
    /// ```swift
    /// let lengths = strings.map { $0.count }
    /// ```
    ///
    /// ## Thread Safety
    ///
    /// The callback may be invoked on any thread/queue depending on the
    /// underlying computation. Callers should not assume any particular
    /// execution context.
    public struct Callback<Value: Sendable>: Sendable {
        /// The underlying computation.
        ///
        /// Invoke this with a callback to receive the value when ready.
        /// The callback will be invoked exactly once.
        public let run: @Sendable (@escaping @Sendable (Value) -> Void) -> Void

        /// Creates a callback with a deferred computation.
        ///
        /// - Parameter run: A function that takes a callback and invokes it
        ///   exactly once with the computed value when ready.
        public init(run: @escaping @Sendable (_ callback: @escaping @Sendable (Value) -> Void) -> Void) {
            self.run = run
        }

        /// Creates a callback with an immediate value.
        ///
        /// The callback is invoked synchronously with the value.
        ///
        /// - Parameter value: The value to wrap.
        public init(value: Value) {
            self.run = { callback in callback(value) }
        }

        /// Transforms the computed value.
        ///
        /// The transformation is applied when the callback runs,
        /// after the original value is computed.
        ///
        /// - Parameter transform: A function to apply to the value.
        /// - Returns: A callback that produces the transformed value.
        public func map<NewValue: Sendable>(
            _ transform: @escaping @Sendable (Value) -> NewValue
        ) -> Callback<NewValue> {
            Callback<NewValue> { callback in
                self.run { value in
                    callback(transform(value))
                }
            }
        }
    }
}

// MARK: - Swift Concurrency Bridge

#if !hasFeature(Embedded)
extension Async.Callback {
    /// Awaits the computed value using Swift concurrency.
    ///
    /// Bridges the callback-based API to Swift's async/await.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation context for the operation.
    ///
    /// - Returns: The computed value.
    public func value(
        isolation: isolated (any Actor)? = #isolation
    ) async -> Value {
        await withCheckedContinuation { continuation in
            self.run { value in
                continuation.resume(returning: value)
            }
        }
    }

    /// Creates a callback from a Swift async function.
    ///
    /// The async operation is started when `run` is called.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation context for the operation.
    ///   - operation: An async operation that produces the value.
    ///
    /// - Returns: A callback that bridges the async operation.
    public static func async(
        isolation: isolated (any Actor)? = #isolation,
        _ operation: @escaping @Sendable () async -> Value
    ) -> Self {
        Self { callback in
            Task {
                let value = await operation()
                callback(value)
            }
        }
    }
}
#endif

// MARK: - Composition

extension Async.Callback {
    /// Chains a dependent computation.
    ///
    /// The transform receives the computed value and returns a new callback
    /// that produces the final result.
    ///
    /// - Parameter transform: A function that takes the value and returns
    ///   a callback for the next computation.
    /// - Returns: A callback that runs both computations in sequence.
    public func flatMap<NewValue: Sendable>(
        _ transform: @escaping @Sendable (Value) -> Async.Callback<NewValue>
    ) -> Async.Callback<NewValue> {
        Async.Callback<NewValue> { callback in
            self.run { value in
                transform(value).run(callback)
            }
        }
    }
}
