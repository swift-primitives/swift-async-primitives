// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025-2026 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Buffer_Primitive
public import Buffer_Ring_Bounded_Primitive
public import Buffer_Ring_Primitive
public import Column_Primitives
public import Memory_Allocator_Primitive
public import Memory_Heap_Primitives
public import Queue_Primitives
public import Storage_Contiguous_Primitives

// MARK: - Pop Eligible

extension Queue_Primitives.Queue where S: ~Copyable {
    // swiftlint:disable:next workaround_marker_present
    // WORKAROUND: popEligible is a compound identifier [API-NAME-002]
    // WHY: Property.Inout cannot express method-level `where ==` constraints
    // WHEN TO REMOVE: When Swift supports constrained Property.Inout extensions with same-type requirements
    // TRACKING: Async.Waiter.Queue unification
    /// Pops the first eligible (non-flagged) entry.
    ///
    /// Pops entries from the front until a non-flagged entry is found.
    /// Flagged entries encountered are enqueued to `flagged`.
    ///
    /// - Parameter flagged: Queue to collect flagged entries into.
    /// - Returns: The first eligible entry, or `nil` if none found.
    @inlinable
    public mutating func popEligible<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        flaggedInto flagged: inout Queue_Primitives.Queue<Async.Waiter.Queue.Flagged<Outcome, Metadata>>
    ) -> S.Element? where S == Column.Ring<Async.Waiter.Entry<Outcome, Metadata>> {
        while !isEmpty {
            guard let entry = dequeue() else { break }
            guard let reason = entry.flag.reason else {
                return entry
            }
            flagged.enqueue(Async.Waiter.Queue.Flagged(reason: reason, entry: entry))
        }
        return nil
    }
}

// MARK: - Reap Flagged

extension Queue_Primitives.Queue where S: ~Copyable {
    // swiftlint:disable:next workaround_marker_present
    // WORKAROUND: reapFlagged is a compound identifier [API-NAME-002]
    // WHY: Property.Inout cannot express method-level `where ==` constraints
    // WHEN TO REMOVE: When Swift supports constrained Property.Inout extensions with same-type requirements
    // TRACKING: Async.Waiter.Queue unification
    /// Reaps all flagged entries via drain+rebuild.
    ///
    /// Drains the queue, collecting flagged entries into `flagged` and
    /// re-enqueuing non-flagged entries back to the queue.
    ///
    /// - Parameter flagged: Queue to collect flagged entries into.
    @inlinable
    public mutating func reapFlagged<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        into flagged: inout Queue_Primitives.Queue<Async.Waiter.Queue.Flagged<Outcome, Metadata>>
    ) where S == Column.Ring<Async.Waiter.Entry<Outcome, Metadata>> {
        var survivors = Queue_Primitives.Queue<Async.Waiter.Entry<Outcome, Metadata>>()

        while !isEmpty {
            guard let entry = dequeue() else { break }
            if let reason = entry.flag.reason {
                flagged.enqueue(Async.Waiter.Queue.Flagged(reason: reason, entry: entry))
            } else {
                survivors.enqueue(entry)
            }
        }

        // Re-enqueue survivors
        survivors.drain { entry in
            self.enqueue(entry)
        }
    }
}

// MARK: - The BOUNDED column (flag-aware ops)
//
// Async.Waiter's bounded-queue surface pins to `S == Column.Ring<Entry>.Bounded`:
// overflow on these invariant-protected paths is a logic error, never a growth
// trigger. Merged from the dissolved bounded-column file (Round M C1 — the
// filename named a retired spelling; one topic file per the Queue+Columns
// precedent).

// MARK: - Push (Unchecked)

extension Queue_Primitives.Queue where S: ~Copyable {
    /// Pushes an entry to the back, trapping if full.
    ///
    /// Use when overflow indicates a logic error (invariant-protected paths).
    ///
    /// - Parameter entry: The entry to push (ownership transferred).
    /// - Precondition: Queue must not be full.
    @inlinable
    public mutating func push<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        unchecked entry: consuming S.Element
    ) where S == Column.Ring<Async.Waiter.Entry<Outcome, Metadata>>.Bounded {
        // WHY: overflow on an invariant-protected path is a logic error — trap.
        // `.full` is the bounded enqueue's only throw.
        // swift-format-ignore: NeverUseForceTry
        // swiftlint:disable:next force_try
        try! enqueue(entry)
    }
}

// MARK: - Pop Eligible

extension Queue_Primitives.Queue where S: ~Copyable {
    // swiftlint:disable:next workaround_marker_present
    // WORKAROUND: popEligible is a compound identifier [API-NAME-002]
    // WHY: Property.Inout cannot express method-level `where ==` constraints
    // WHEN TO REMOVE: When Swift supports constrained Property.Inout extensions with same-type requirements
    // TRACKING: Async.Waiter.Queue unification
    /// Pops the first eligible (non-flagged) entry.
    ///
    /// Pops entries from the front until a non-flagged entry is found.
    /// Flagged entries encountered are enqueued to `flagged`.
    ///
    /// - Parameter flagged: Queue to collect flagged entries into.
    /// - Returns: The first eligible entry, or `nil` if none found.
    @inlinable
    public mutating func popEligible<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        flaggedInto flagged: inout Queue_Primitives.Queue<Async.Waiter.Queue.Flagged<Outcome, Metadata>>
    ) -> S.Element? where S == Column.Ring<Async.Waiter.Entry<Outcome, Metadata>>.Bounded {
        while !isEmpty {
            guard let entry = dequeue() else { break }
            guard let reason = entry.flag.reason else {
                return entry
            }
            flagged.enqueue(Async.Waiter.Queue.Flagged(reason: reason, entry: entry))
        }
        return nil
    }
}

// MARK: - Reap Flagged

extension Queue_Primitives.Queue where S: ~Copyable {
    // swiftlint:disable:next workaround_marker_present
    // WORKAROUND: reapFlagged is a compound identifier [API-NAME-002]
    // WHY: Property.Inout cannot express method-level `where ==` constraints
    // WHEN TO REMOVE: When Swift supports constrained Property.Inout extensions with same-type requirements
    // TRACKING: Async.Waiter.Queue unification
    /// Reaps all flagged entries via drain+rebuild.
    ///
    /// Drains the queue, collecting flagged entries into `flagged` and
    /// re-pushing non-flagged entries back to the queue.
    ///
    /// - Parameter flagged: Queue to collect flagged entries into.
    @inlinable
    public mutating func reapFlagged<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        into flagged: inout Queue_Primitives.Queue<Async.Waiter.Queue.Flagged<Outcome, Metadata>>
    ) where S == Column.Ring<Async.Waiter.Entry<Outcome, Metadata>>.Bounded {
        var survivors = Queue_Primitives.Queue<Async.Waiter.Entry<Outcome, Metadata>>()

        while !isEmpty {
            guard let entry = dequeue() else { break }
            if let reason = entry.flag.reason {
                flagged.enqueue(Async.Waiter.Queue.Flagged(reason: reason, entry: entry))
            } else {
                survivors.enqueue(entry)
            }
        }

        // Re-push survivors (queue was just drained, so capacity is available).
        survivors.drain { entry in
            // WHY: the queue was just drained — capacity is available; trap on
            // the impossible overflow rather than swallow it.
            // swift-format-ignore: NeverUseForceTry
            // swiftlint:disable:next force_try
            try! self.enqueue(entry)
        }
    }
}
