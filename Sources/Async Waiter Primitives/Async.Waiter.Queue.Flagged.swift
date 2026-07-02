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

extension Async.Waiter.Queue.Flagged {
    /// Resolves the outcome from the flag reason and builds the resumption,
    /// consuming self in one step.
    ///
    /// Deliberately NOT `@inlinable`, and deliberately here rather than at
    /// the call site: the Windows 6.3.3+Asserts toolchain's
    /// MoveOnlyAddressChecker asserts (MoveOnlyAddressCheckerUtils.cpp:1829)
    /// when a CLIENT module partially consumes `Split`
    /// (`split.entry.resumption(with:)`); performing the partial consume in
    /// the defining module takes the checker's same-module path.
    ///
    /// - Parameter makeOutcome: Maps the flag reason to the waiter outcome.
    ///   Metrics attribution belongs inside this closure (a tuple return is
    ///   unavailable: `Resumption` is noncopyable and tuples cannot carry
    ///   noncopyable elements).
    /// - Returns: The resumption carrying the resolved outcome.
    public consuming func resumption(
        resolving makeOutcome: (Async.Waiter.Flag.Reason) -> Outcome
    ) -> Async.Waiter.Resumption {
        let split = self.split()
        return split.entry.resumption(with: makeOutcome(split.reason))
    }
}
