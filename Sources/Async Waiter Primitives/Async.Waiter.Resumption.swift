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

extension Async.Waiter {
    /// An executable thunk for deferred continuation resumption.
    ///
    /// ## Deferred Resumption Pattern
    ///
    /// **INVARIANT:** Continuations are NEVER resumed while holding a lock.
    ///
    /// Under lock, compute outcomes and create `Resumption` instances.
    /// After releasing the lock, call `resume()` on each instance.
    ///
    /// This pattern prevents:
    /// - Deadlock from user code running under lock
    /// - Priority inversion
    /// - Unbounded lock hold times
    ///
    /// ## Usage
    ///
    /// ```swift
    /// var pending: [Async.Waiter.Resumption] = []
    ///
    /// lock.lock()
    /// // ... compute outcomes, create resumptions ...
    /// pending.append(Async.Waiter.Resumption {
    ///     continuation.resume(returning: outcome)
    /// })
    /// lock.unlock()
    ///
    /// // Resume AFTER lock released
    /// for p in pending {
    ///     p.resume()
    /// }
    /// ```
    ///
    /// ## Thread Safety
    ///
    /// `Resumption` is `Sendable`. The closure captures values, not references
    /// to mutable state. Each resumption should be executed exactly once.
    public struct Resumption: Sendable {
        @usableFromInline
        let _resume: @Sendable () -> Void

        /// Creates a resumption thunk.
        ///
        /// - Parameter action: The action to perform when `resume()` is called.
        ///   Typically resumes a continuation with a computed outcome.
        @inlinable
        public init(_ action: @escaping @Sendable () -> Void) {
            self._resume = action
        }

        /// Executes the resumption.
        ///
        /// This should be called exactly once, after releasing any locks.
        @inlinable
        public func resume() {
            _resume()
        }
    }
}
