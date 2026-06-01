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

public import Queue_Primitives

// MARK: - Pop Eligible

extension Queue_Primitives.Queue where Element: ~Copyable {
    /// Pops the first eligible (non-flagged) entry.
    ///
    /// Pops entries from the front until a non-flagged entry is found.
    /// Flagged entries encountered are enqueued to `flagged`.
    ///
    /// - Parameter flagged: Queue to collect flagged entries into.
    /// - Returns: The first eligible entry, or `nil` if none found.
    // WORKAROUND: popEligible is a compound identifier [API-NAME-002]
    // WHY: Property.Inout cannot express method-level `where Element ==` constraints
    // WHEN TO REMOVE: When Swift supports constrained Property.Inout extensions with same-type requirements
    // TRACKING: Async.Waiter.Queue unification
    @inlinable
    public mutating func popEligible<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        flaggedInto flagged: inout Queue_Primitives.Queue<Async.Waiter.Queue.Flagged<Outcome, Metadata>>
    ) -> Element? where Element == Async.Waiter.Entry<Outcome, Metadata> {
        while !isEmpty {
            let entry = dequeue()!
            if let reason = entry.flag.reason {
                flagged.enqueue(Async.Waiter.Queue.Flagged(reason: reason, entry: entry))
            } else {
                return entry
            }
        }
        return nil
    }
}

// MARK: - Reap Flagged

extension Queue_Primitives.Queue where Element: ~Copyable {
    /// Reaps all flagged entries via drain+rebuild.
    ///
    /// Drains the queue, collecting flagged entries into `flagged` and
    /// re-enqueuing non-flagged entries back to the queue.
    ///
    /// - Parameter flagged: Queue to collect flagged entries into.
    // WORKAROUND: reapFlagged is a compound identifier [API-NAME-002]
    // WHY: Property.Inout cannot express method-level `where Element ==` constraints
    // WHEN TO REMOVE: When Swift supports constrained Property.Inout extensions with same-type requirements
    // TRACKING: Async.Waiter.Queue unification
    @inlinable
    public mutating func reapFlagged<Outcome: Sendable, Metadata: ~Copyable & Sendable>(
        into flagged: inout Queue_Primitives.Queue<Async.Waiter.Queue.Flagged<Outcome, Metadata>>
    ) where Element == Async.Waiter.Entry<Outcome, Metadata> {
        var survivors = Queue_Primitives.Queue<Async.Waiter.Entry<Outcome, Metadata>>()

        while !isEmpty {
            let entry = dequeue()!
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
