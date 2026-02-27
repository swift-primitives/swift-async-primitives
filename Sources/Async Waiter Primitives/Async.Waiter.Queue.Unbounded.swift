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
    /// Unbounded FIFO queue with automatic growth.
    ///
    /// A waiter queue that grows as needed. Push operations always succeed.
    ///
    /// ## Design
    ///
    /// - Backing storage: `Buffer<Entry>.Ring` (~Copyable growable ring buffer)
    /// - Unbounded: push always succeeds (grows when needed)
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
    public struct Unbounded<Outcome: Sendable, Metadata: ~Copyable & Sendable>: ~Copyable {
        public typealias Entry = Async.Waiter.Entry<Outcome, Metadata>
        public typealias Flagged = Async.Waiter.Queue.Flagged<Outcome, Metadata>

        @usableFromInline
        var _storage: Buffer<Entry>.Ring

        /// Creates an unbounded queue.
        ///
        /// - Parameter minimumCapacity: Initial capacity hint (default: 8).
        @inlinable
        public init(minimumCapacity: Index<Entry>.Count = Index<Entry>.Count(8 as UInt)) {
            self._storage = Buffer<Entry>.Ring(minimumCapacity: minimumCapacity)
        }

        /// The current number of waiters in the queue.
        @inlinable
        public var count: Index<Entry>.Count { _storage.count }

        /// Whether the queue is empty.
        @inlinable
        public var isEmpty: Bool { _storage.isEmpty }

        /// The current capacity of the queue.
        @inlinable
        public var capacity: Index<Entry>.Count { _storage.capacity }
    }
}

// MARK: - Push

extension Async.Waiter.Queue.Unbounded {
    /// Pushes an entry to the back of the queue.
    ///
    /// Always succeeds (grows storage if needed).
    ///
    /// - Parameter entry: The entry to push (ownership transferred).
    @inlinable
    public mutating func push(_ entry: consuming Entry) {
        _storage.push.back(entry)
    }
}

// MARK: - Pop

extension Async.Waiter.Queue.Unbounded {
    /// Pops the oldest entry from the front (FIFO).
    ///
    /// Returns the entry regardless of flag state.
    ///
    /// - Returns: The oldest entry, or `nil` if empty.
    @inlinable
    public mutating func popFront() -> Entry? {
        guard !_storage.isEmpty else { return nil }
        return _storage.pop.front()
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
        while !_storage.isEmpty {
            let entry = _storage.pop.front()
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

extension Async.Waiter.Queue.Unbounded {
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

        while !_storage.isEmpty {
            let entry = _storage.pop.front()
            if let reason = entry.flag.reason {
                flagged.append(Flagged(reason: reason, entry: entry))
            } else {
                survivors.append(entry)
            }
        }

        // Re-push survivors
        survivors.drain { entry in
            _storage.push.back(entry)
        }
    }

    /// Drains all entries from the queue.
    ///
    /// Use for shutdown scenarios where all waiters must be processed.
    ///
    /// - Parameter body: Closure that consumes each entry.
    @inlinable
    public mutating func drainAll(_ body: (consuming Entry) -> Void) {
        while !_storage.isEmpty {
            body(_storage.pop.front())
        }
    }
}

// MARK: - Sendable

extension Async.Waiter.Queue.Unbounded: @unchecked Sendable where Metadata: Sendable {}
