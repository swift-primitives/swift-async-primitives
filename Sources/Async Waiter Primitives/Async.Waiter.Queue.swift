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

public import Identity_Primitives

extension Async.Waiter {
    /// Namespace for waiter queue types.
    ///
    /// Provides `Bounded` and `Unbounded` queue variants for managing waiter entries.
    ///
    /// ## Design Principles
    ///
    /// 1. **No closures in queue operations** - Operations return raw data (entries, flagged tuples).
    ///    Callers compute outcomes and create resumptions outside locks.
    ///
    /// 2. **No resumption under lock** - Queues never call `resume()`. They produce `Entry` values
    ///    that callers convert to `Resumption` thunks outside critical sections.
    ///
    /// 3. **~Copyable storage** - Both queue types use move-only backing storage, preventing
    ///    accidental duplication of entries and enforcing exactly-once resumption semantics.
    ///
    /// ## Synchronization Contract
    ///
    /// **CRITICAL:** Queue types are NOT internally synchronized.
    /// - All queue operations (`push`, `popFront`, `drain*`) MUST be called while holding
    ///   the caller's mutex.
    /// - `Flag` bits may be set concurrently (they are atomic), but queue structure must
    ///   never be mutated concurrently.
    /// - Violating this contract causes undefined behavior.
    ///
    /// ## Usage Pattern
    ///
    /// ```swift
    /// var queue = Async.Waiter.Queue.Bounded<MyOutcome, Token>(capacity: 64)
    ///
    /// // Under lock: collect data
    /// let (eligible, flagged) = lock.withLock { state in
    ///     var flagged = Async.Waiter.Queue.Drain<...>()
    ///     let eligible = state.queue.popEligible(flaggedInto: &flagged)
    ///     return (eligible, flagged)
    /// }
    ///
    /// // Outside lock: compute outcomes, create resumptions, execute
    /// var pending: [Async.Waiter.Resumption] = []
    /// flagged.drain { entry, reason in
    ///     let outcome = computeOutcome(reason)  // Domain logic
    ///     pending.append(entry.resumption(with: outcome))
    /// }
    /// if let entry = eligible {
    ///     pending.append(entry.resumption(with: .success(resource)))
    /// }
    /// for p in pending { p.resume() }
    /// ```
    public enum Queue {}
}

// MARK: - Metadata (Backward Compatibility)

extension Async.Waiter.Queue {
    /// Phantom tag for waiter metadata.
    public enum MetadataTag {}

    /// Caller-defined opaque metadata for waiter entries.
    ///
    /// Interpretation is entirely up to the caller. Common uses include
    /// slot indices, sequence numbers, or deadline timestamps. The Tagged
    /// wrapper prevents accidental mixing with other UInt64 values.
    public typealias Metadata = Tagged<MetadataTag, UInt64>
}

// MARK: - Flagged Entry

extension Async.Waiter.Queue {
    /// A flagged entry that was removed from the queue.
    ///
    /// Returned by operations that scan for and remove flagged entries.
    /// Caller computes outcome based on `reason` and creates resumption outside lock.
    public struct Flagged<Outcome: Sendable, Metadata: ~Copyable & Sendable>: ~Copyable, Sendable {
        /// The reason the entry was flagged (cancelled or timed out).
        public let reason: Async.Waiter.Flag.Reason

        /// The flagged entry (ownership transferred).
        public var entry: Async.Waiter.Entry<Outcome, Metadata>

        @inlinable
        public init(reason: Async.Waiter.Flag.Reason, entry: consuming Async.Waiter.Entry<Outcome, Metadata>) {
            self.reason = reason
            self.entry = entry
        }

        /// Deconstructs this flagged value into its components, consuming self.
        ///
        /// Makes the ownership transition explicit in one step.
        ///
        /// - Returns: A `Split` containing reason and entry with ownership transferred.
        @inlinable
        public consuming func split() -> Split {
            Split(reason: reason, entry: entry)
        }

        /// Result of splitting a flagged entry into its components.
        @frozen
        public struct Split: ~Copyable, Sendable {
            /// The reason the entry was flagged.
            public let reason: Async.Waiter.Flag.Reason

            /// The flagged entry (ownership transferred).
            public var entry: Async.Waiter.Entry<Outcome, Metadata>

            @inlinable
            public init(reason: Async.Waiter.Flag.Reason, entry: consuming Async.Waiter.Entry<Outcome, Metadata>) {
                self.reason = reason
                self.entry = entry
            }
        }
    }
}
