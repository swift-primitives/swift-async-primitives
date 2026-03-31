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

// MARK: - Flagged Operations

extension Async.Waiter.Queue.Flagged {
    /// Deconstructs this flagged value into its components, consuming self.
    ///
    /// Makes the ownership transition explicit in one step.
    ///
    /// - Returns: A `Split` containing reason and entry with ownership transferred.
    @inlinable
    public consuming func split() -> Split {
        Split(reason: reason, entry: entry)
    }
}
