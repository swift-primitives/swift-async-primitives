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
    /// A deferred value computation that preserves caller isolation.
    ///
    /// `Callback` wraps a computation that produces a value asynchronously.
    /// The computation inherits the caller's isolation context — if called
    /// from `@MainActor`, it executes on `@MainActor` with no thread hop.
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
    /// let callback = Async.Callback<String> { "Computed result" }
    /// ```
    ///
    /// ## Running the Computation
    ///
    /// ```swift
    /// let value = await callback()
    /// ```
    ///
    /// ## Transforming Values
    ///
    /// ```swift
    /// let lengths = strings.map { $0.count }
    /// let value = await lengths()
    /// ```
    public struct Callback<Value> {
        @usableFromInline
        let operation: nonisolated(nonsending) () async -> Value

        /// Creates a callback with a deferred computation.
        ///
        /// The operation inherits the caller's isolation context and executes
        /// on the caller's executor. If the operation body is synchronous,
        /// no suspension occurs.
        ///
        /// - Parameter operation: An async operation that produces the value.
        @inlinable
        public init(
            _ operation: nonisolated(nonsending) @escaping () async -> Value
        ) {
            self.operation = operation
        }

        /// Creates a callback with an immediate value.
        ///
        /// - Parameter value: The value to wrap.
        @inlinable
        public init(value: Value) {
            self.operation = { value }
        }

        /// Executes the computation and returns the value.
        ///
        /// Inherits the caller's isolation context via SE-0420.
        /// If the underlying operation is synchronous, this completes
        /// without suspension.
        @inlinable
        public func callAsFunction(
            isolation: isolated (any Actor)? = #isolation
        ) async -> Value {
            await operation()
        }

        /// Transforms the computed value with a synchronous closure.
        ///
        /// The transform executes within the caller's isolation context.
        ///
        /// - Parameter transform: A function to apply to the value.
        /// - Returns: A callback that produces the transformed value.
        @inlinable
        public func map<NewValue>(
            _ transform: @escaping (Value) -> NewValue
        ) -> Async.Callback<NewValue> {
            .init { transform(await self()) }
        }

        /// Chains a dependent computation.
        ///
        /// - Parameter transform: A function that takes the value and returns
        ///   a callback for the next computation.
        /// - Returns: A callback that runs both computations in sequence.
        @inlinable
        public func flatMap<NewValue>(
            _ transform: @escaping (Value) -> Async.Callback<NewValue>
        ) -> Async.Callback<NewValue> {
            .init { await transform(await self())() }
        }
    }
}

// MARK: - Legacy CPS Bridge

#if !hasFeature(Embedded)
extension Async.Callback where Value: Sendable {
    /// Creates a callback by wrapping a CPS-style completion handler.
    ///
    /// Use when bridging OS callbacks, network completions, or other code
    /// that fires a completion handler on an arbitrary thread.
    ///
    /// - Parameter cps: A function that takes a completion callback and
    ///   invokes it exactly once with the computed value when ready.
    @inlinable
    public init(
        wrapping cps: @escaping @Sendable (
            @escaping @Sendable (Value) -> Void
        ) -> Void
    ) {
        self.init {
            await withCheckedContinuation { continuation in
                cps { value in
                    continuation.resume(returning: value)
                }
            }
        }
    }
}
#endif
