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
    /// A waiter entry with continuation, flag, and optional metadata.
    ///
    /// ## Design
    ///
    /// Entry is the fundamental unit of waiting:
    /// - `continuation`: Resume point for the suspended task
    /// - `flag`: Atomic cancellation/timeout signaling
    /// - `metadata`: Caller-defined data (slot index, deadline, etc.)
    ///
    /// ## ~Copyable
    ///
    /// Entry is `~Copyable` to enforce single-use semantics:
    /// - Each entry can only be resumed once
    /// - Prevents accidental double-resume bugs
    /// - Metadata can be ~Copyable (e.g., move-only handles)
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let entry = Async.Waiter.Entry(
    ///     continuation: continuation,
    ///     flag: flag,
    ///     metadata: slotIndex
    /// )
    ///
    /// // Later, consume entry to create resumption
    /// let resumption = entry.resumption(with: .success(value))
    /// resumption.resume()  // After lock released
    /// ```
    public struct Entry<Outcome: Sendable, Metadata: ~Copyable & Sendable>: ~Copyable, Sendable {
        /// Continuation to resume when outcome is determined.
        public let continuation: Async.Continuation<Outcome>

        /// External flag for cancellation/timeout signaling.
        public let flag: Async.Waiter.Flag

        /// Caller-defined metadata.
        ///
        /// Mutable to allow in-place updates without re-creating the entry.
        /// Common uses: slot indices, sequence numbers, deadline timestamps.
        public var metadata: Metadata

        /// Creates a waiter entry.
        ///
        /// - Parameters:
        ///   - continuation: The continuation to resume.
        ///   - flag: The flag for external signaling.
        ///   - metadata: Caller-defined value (ownership transferred).
        @inlinable
        public init(
            continuation: Async.Continuation<Outcome>,
            flag: Async.Waiter.Flag,
            metadata: consuming Metadata
        ) {
            self.continuation = continuation
            self.flag = flag
            self.metadata = metadata
        }
    }
}

// MARK: - Resumption

extension Async.Waiter.Entry {
    /// Creates a resumption thunk for this entry with the given outcome.
    ///
    /// Consumes the entry to enforce single-use semantics.
    ///
    /// - Parameter outcome: The outcome to resume the continuation with.
    /// - Returns: A resumption thunk to execute after releasing the lock.
    @inlinable
    public consuming func resumption(with outcome: Outcome) -> Async.Waiter.Resumption {
        let cont = self.continuation
        _ = consume self
        return Async.Waiter.Resumption {
            cont.resume(returning: outcome)
        }
    }
}

// MARK: - Convenience for Void Metadata

extension Async.Waiter.Entry where Metadata == Void {
    /// Creates a waiter entry without metadata.
    ///
    /// - Parameters:
    ///   - continuation: The continuation to resume.
    ///   - flag: The flag for external signaling.
    @inlinable
    public init(
        continuation: Async.Continuation<Outcome>,
        flag: Async.Waiter.Flag
    ) {
        self.continuation = continuation
        self.flag = flag
        self.metadata = ()
    }
}
