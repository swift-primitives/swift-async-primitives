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

public import Buffer_Primitives

extension Async.Waiter.Queue {
    /// Bounded FIFO queue with fixed capacity.
    ///
    /// A waiter queue with a maximum capacity. Push operations return the rejected
    /// element when full, allowing the caller to handle overflow.
    ///
    /// ## Design
    ///
    /// - Backing storage: `Buffer.Ring.Bounded` (~Copyable ring buffer)
    /// - Fixed capacity: push returns rejected element when full
    /// - No closures: operations return raw data, callers compute outcomes outside locks
    /// - ~Copyable: prevents accidental duplication of entries
    ///
    /// ## Invariants
    ///
    /// - **Armed-at-enqueue**: All entries in the queue have valid continuations.
    ///   There is no "unarmed" state - entries are fully armed at creation.
    ///
    /// - **No resumption under lock**: Queue operations never call `resume()`.
    ///   They return entries; callers create and execute resumptions outside locks.
    ///
    /// - **Exactly-once (by type)**: Entry is `~Copyable` with `consuming resumption()`.
    ///   The compiler enforces that each entry produces exactly one resumption.
    ///
    /// ## Thread Safety
    ///
    /// Not internally synchronized. All operations must be called under external lock.
    public struct Bounded<Outcome: Sendable, Metadata: ~Copyable & Sendable>: ~Copyable {
        public typealias Entry = Async.Waiter.Entry<Outcome, Metadata>
        public typealias Flagged = Async.Waiter.Queue.Flagged<Outcome, Metadata>

        @usableFromInline
        var _storage: Buffer.Ring.Bounded<Entry>

        /// Creates a bounded queue with the specified capacity.
        ///
        /// - Parameter capacity: Maximum number of waiters. Must be at least 1.
        @inlinable
        public init(capacity: Int) {
            self._storage = Buffer.Ring.Bounded<Entry>(capacity: capacity)
        }

        /// The fixed capacity of the queue.
        @inlinable
        public var capacity: Int { _storage.capacity }

        /// The current number of waiters in the queue.
        @inlinable
        public var count: Int { _storage.count }

        /// Whether the queue is empty.
        @inlinable
        public var isEmpty: Bool { _storage.isEmpty }

        /// Whether the queue is at capacity.
        @inlinable
        public var isFull: Bool { _storage.isFull }
    }
}

// MARK: - Push

extension Async.Waiter.Queue.Bounded {
    /// Pushes an entry to the back of the queue.
    ///
    /// - Parameter entry: The entry to push (ownership transferred on success).
    /// - Returns: `nil` if successfully pushed, or the rejected entry if full.
    ///
    /// Ownership semantics:
    /// - On success: entry is consumed, returns `nil`
    /// - On failure: entry is returned to caller, caller retains ownership
    @inlinable
    public mutating func push(_ entry: consuming Entry) -> Entry? {
        // Buffer.Ring.Bounded.push returns nil on success, element on failure
        // This preserves ownership: rejected entry goes back to caller
        _storage.push(entry)
    }

    /// Pushes an entry to the back, trapping if full.
    ///
    /// Use when overflow indicates a logic error (invariant-protected paths).
    ///
    /// - Parameter entry: The entry to push (ownership transferred).
    /// - Precondition: Queue must not be full.
    @inlinable
    public mutating func push(unchecked entry: consuming Entry) {
        _storage.push(unchecked: entry)
    }
}

// MARK: - Pop

extension Async.Waiter.Queue.Bounded {
    /// Pops the oldest entry from the front (FIFO).
    ///
    /// Returns the entry regardless of flag state.
    ///
    /// - Returns: The oldest entry, or `nil` if empty.
    @inlinable
    public mutating func popFront() -> Entry? {
        _storage.popFront()
    }

    /// Pops the first eligible (non-flagged) entry.
    ///
    /// Pops entries from the front until a non-flagged entry is found.
    /// Flagged entries encountered are appended to `flagged`.
    ///
    /// - Parameter flagged: Drain to append flagged entries to.
    /// - Returns: The first eligible entry, or `nil` if none found.
    @inlinable
    public mutating func popEligible(
        flaggedInto flagged: inout Async.Waiter.Queue.Drain<Flagged>
    ) -> Entry? {
        while let entry = _storage.popFront() {
            if let reason = entry.flag.reason {
                flagged.append(Flagged(reason: reason, entry: entry))
            } else {
                return entry
            }
        }
        return nil
    }
}

// MARK: - Reap

extension Async.Waiter.Queue.Bounded {
    /// Reaps all flagged entries via drain+rebuild.
    ///
    /// Drains the queue, collecting flagged entries into `flagged` and
    /// re-pushing non-flagged entries back to the queue.
    ///
    /// - Parameter flagged: Drain to append flagged entries to.
    @inlinable
    public mutating func reapFlagged(into flagged: inout Async.Waiter.Queue.Drain<Flagged>) {
        // Collect survivors in a temporary drain
        var survivors = Async.Waiter.Queue.Drain<Entry>()

        _storage.drain { entry in
            if let reason = entry.flag.reason {
                flagged.append(Flagged(reason: reason, entry: entry))
            } else {
                survivors.append(entry)
            }
        }

        // Re-push survivors (queue was just drained, so capacity is available)
        survivors.drain { entry in
            _storage.push(unchecked: entry)
        }
    }

    /// Drains all entries from the queue.
    ///
    /// Use for shutdown scenarios where all waiters must be processed.
    ///
    /// - Parameter body: Closure that consumes each entry.
    @inlinable
    public mutating func drainAll(_ body: (consuming Entry) -> Void) {
        _storage.drain(body)
    }
}

// MARK: - Sendable

extension Async.Waiter.Queue.Bounded: @unchecked Sendable where Metadata: Sendable {}
