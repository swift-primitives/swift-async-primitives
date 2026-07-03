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

public import Queue_Primitives
public import Column_Primitives
public import Buffer_Ring_Primitive
public import Buffer_Ring_Bounded_Primitive
public import Storage_Contiguous_Primitives
import Memory_Heap_Primitives
import Memory_Allocator_Primitive
import Buffer_Primitive

extension Async.Waiter {
    /// Namespace for waiter queue types.
    ///
    /// Queue types are backed by queue-primitives (`Queue<Entry>.Fixed` and `Queue<Entry>`),
    /// with flag-aware operations provided as extensions.
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
    /// - All queue operations (`push`, `dequeue`, `drain`) MUST be called while holding
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
    /// // Outside lock: resume inline
    /// flagged.drain { flaggedEntry in
    ///     flaggedEntry.entry.resumption(with: computeOutcome(flaggedEntry.reason)).resume()
    /// }
    /// if let entry = eligible {
    ///     entry.resumption(with: .success(resource)).resume()
    /// }
    /// ```
    public enum Queue {}
}

// MARK: - Queue Type Aliases

extension Async.Waiter.Queue {
    /// A bounded waiter queue with fixed capacity.
    ///
    /// Backed by `Queue` over the BOUNDED RING column (the W5 re-spell: the old
    /// `Queue<Entry>.Fixed` dissolved into the column per the leg-5 ledger).
    /// Flag-aware operations (`popEligible`, `reapFlagged`) are provided as extensions.
    public typealias Bounded<Outcome: Sendable, Metadata: ~Copyable & Sendable> =
        Queue_Primitives.Queue<Async.Waiter.Entry<Outcome, Metadata>>.Bounded

    /// An unbounded waiter queue with automatic growth.
    ///
    /// Backed by `Queue` over the growable RING column (the W5 re-spell of the
    /// withdrawn element-keyed `Queue<Entry>`). Flag-aware operations
    /// (`popEligible`, `reapFlagged`) are provided as extensions.
    public typealias Unbounded<Outcome: Sendable, Metadata: ~Copyable & Sendable> =
        Queue_Primitives.Queue<Async.Waiter.Entry<Outcome, Metadata>>

    /// A drainable collection of ~Copyable elements.
    ///
    /// Used to collect flagged entries from queue operations.
    /// Elements are consumed via `drain { }` or `dequeue()`.
    public typealias Drain<Element: ~Copyable> = Queue_Primitives.Queue<Element>
}
