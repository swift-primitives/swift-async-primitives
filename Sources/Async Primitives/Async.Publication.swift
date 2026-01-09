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
    /// A cancellation-safe publication slot for racing to claim a value.
    ///
    /// Designed for the "publish then take-and-clear" pattern used in
    /// `withTaskCancellationHandler` where both the operation closure and
    /// `onCancel` race to claim a published token.
    ///
    /// ## Semantics
    /// - Starts empty (or with an initial value)
    /// - `publish(_:)` sets a value (overwrites any previous value)
    /// - `take()` atomically takes and clears; returns `nil` if empty or already taken
    /// - Exactly one racing caller wins `take()`; others receive `nil` (no trap)
    ///
    /// ## Usage Pattern
    /// ```swift
    /// let publication = Async.Publication<WaitToken>()
    ///
    /// await withTaskCancellationHandler {
    ///     await withCheckedContinuation { continuation in
    ///         // ... install waiter and get value ...
    ///         publication.publish(value)
    ///
    ///         // Close early-cancellation window
    ///         if Task.isCancelled {
    ///             if let taken = publication.take() {
    ///                 // Handle cancellation
    ///             }
    ///         }
    ///     }
    /// } onCancel: { [publication] in
    ///     if let taken = publication.take() {
    ///         // Handle cancellation
    ///     }
    /// }
    /// ```
    ///
    /// ## Exactly-Once Guarantee
    /// The `take()` operation is atomic and winner-takes-all. When both the
    /// operation closure and `onCancel` race to claim the value, exactly one
    /// wins. The other receives `nil` (does not trap).
    ///
    /// ## Capture Safety
    /// This is a reference type (`final class`) that can be safely captured
    /// in `@Sendable` closures using an explicit capture list `[publication]`.
    /// `publish`/`take` are lock-protected; `take` is winner-takes-all and
    /// therefore safe under cancellation races.
    ///
    /// Unlike `Kernel.Handoff.Cell`, this slot:
    /// - May start empty (Cell requires initial value)
    /// - Supports overwrite via `publish` (Cell is one-shot)
    /// - Returns `nil` on losing `take()` (Cell traps on double-take)
    ///
    /// ## Thread Safety
    /// All operations are protected by an internal mutex.
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    public final class Publication<Value: Sendable>: @unchecked Sendable {
        private let _state: Mutex<Value?>

        /// Creates a new publication slot.
        ///
        /// - Parameter initial: Initial value, typically `nil`.
        public init(_ initial: sending Value? = nil) {
            self._state = Mutex(initial)
        }
    }
}

// MARK: - Operations

extension Async.Publication {
    /// Publish a value.
    ///
    /// Overwrites any previously published value that has not yet been taken.
    ///
    /// - Parameter value: The value to publish.
    public func publish(_ value: sending Value) {
        _state.withLock { $0 = value }
    }

    /// Atomically take and clear the value.
    ///
    /// Returns the current value and sets it to `nil` in one atomic operation.
    /// This ensures exactly one caller wins the race to claim the value.
    /// Losers receive `nil` (does not trap).
    ///
    /// - Returns: The published value, or `nil` if not set or already taken.
    public func take() -> Value? {
        _state.withLock { current in
            let value = current
            current = nil
            return value
        }
    }
}
