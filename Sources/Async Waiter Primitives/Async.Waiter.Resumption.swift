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
    /// // Under lock: collect entry data
    /// let (eligible, flagged) = lock.withLock { state in
    ///     var flagged = Async.Waiter.Queue.Drain<...>()
    ///     let eligible = state.queue.popEligible(flaggedInto: &flagged)
    ///     return (eligible, flagged)
    /// }
    ///
    /// // Outside lock: resume inline
    /// flagged.drain { entry, reason in
    ///     entry.resumption(with: computeOutcome(reason)).resume()
    /// }
    /// if let entry = eligible {
    ///     entry.resumption(with: .success(resource)).resume()
    /// }
    /// ```
    ///
    /// ## Thread Safety
    ///
    /// `Resumption` is `Sendable`. The closure captures values, not references
    /// to mutable state. Each resumption is consumed exactly once (enforced
    /// by `~Copyable`).
    public struct Resumption: ~Copyable, Sendable {
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
    }
}

// MARK: - Resume

extension Async.Waiter.Resumption {
    /// Consumes the resumption, executing its action.
    ///
    /// Must be called after releasing any locks.
    @inlinable
    public consuming func resume() {
        _resume()
    }
}
