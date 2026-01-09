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

public import Container_Primitives
public import Identity_Primitives

extension Async.Waiter {
    /// A FIFO queue of waiters with atomic flag support and deferred resumption.
    ///
    /// ## Synchronization Contract
    ///
    /// **CRITICAL:** This type is NOT internally synchronized.
    /// - All queue operations (`enqueue`, `dequeue*`, `reap*`) MUST be called
    ///   while holding the caller's mutex.
    /// - `Flag` bits may be set concurrently (they are atomic), but queue
    ///   structure must never be mutated concurrently.
    /// - Violating this contract causes undefined behavior.
    ///
    /// ## Design
    ///
    /// `Queue` is a building block for implementing waiting patterns:
    /// - FIFO ordering for fairness
    /// - Flag-aware dequeue (reaps cancelled/timed out entries from front)
    /// - Batch reaping via scan+rebuild
    /// - Deferred resumption via `Resumption` thunks
    ///
    /// ## Usage Pattern
    ///
    /// ```swift
    /// let queue = Async.Waiter.Queue<MyOutcome>()
    /// var pending: [Async.Waiter.Resumption] = []
    ///
    /// lock.lock()
    ///
    /// // Enqueue a waiter
    /// queue.enqueue(entry)
    ///
    /// // Dequeue first eligible waiter (dequeues flagged from front, appending
    /// // their resumptions to pending, until a non-flagged entry is found)
    /// if let entry = queue.dequeueEligible(
    ///     into: &pending,
    ///     outcome: { reason, _ in
    ///         switch reason {
    ///         case .cancelled: return .failure(.cancelled)
    ///         case .timedOut: return .failure(.timeout)
    ///         }
    ///     }
    /// ) {
    ///     pending.append(entry.resumption(with: .success(resource)))
    /// }
    ///
    /// // Reap all flagged waiters (scan + rebuild)
    /// queue.reapFlagged(into: &pending) { reason, _ in
    ///     switch reason {
    ///     case .cancelled: return .failure(.cancelled)
    ///     case .timedOut: return .failure(.timeout)
    ///     }
    /// }
    ///
    /// lock.unlock()
    ///
    /// // Resume AFTER lock released (deferred resumption)
    /// for p in pending { p.resume() }
    /// ```
    ///
    /// ## Thread Safety
    ///
    /// Uses `@unchecked Sendable` because internal state is protected by
    /// the caller-provided mutex, not internal synchronization.
    public final class Queue<Outcome: Sendable>: @unchecked Sendable {
        @usableFromInline
        var _entries: Deque<Entry>

        /// Creates an empty waiter queue.
        @inlinable
        public init() {
            self._entries = Deque()
        }

        /// Number of waiters currently in the queue.
        @inlinable
        public var count: Int {
            _entries.count
        }

        /// Whether the queue is empty.
        @inlinable
        public var isEmpty: Bool {
            _entries.isEmpty
        }
    }
}


// MARK: - Metadata

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

// MARK: - Entry

extension Async.Waiter.Queue {
    /// A waiter entry in the queue.
    public struct Entry: Sendable {
        /// Continuation to resume when outcome is determined.
        @usableFromInline
        let continuation: CheckedContinuation<Outcome, Never>

        /// External flag for cancellation/timeout signaling.
        public let flag: Async.Waiter.Flag

        /// Caller-defined opaque metadata.
        ///
        /// Interpretation is entirely up to the caller. Common uses include
        /// slot indices, sequence numbers, or deadline timestamps.
        public let metadata: Metadata

        /// Creates a waiter entry.
        ///
        /// - Parameters:
        ///   - continuation: The continuation to resume.
        ///   - flag: The flag for external signaling.
        ///   - metadata: Caller-defined opaque value (default: 0).
        @inlinable
        public init(
            continuation: CheckedContinuation<Outcome, Never>,
            flag: Async.Waiter.Flag,
            metadata: Metadata = Metadata(0)
        ) {
            self.continuation = continuation
            self.flag = flag
            self.metadata = metadata
        }

        /// Creates a resumption thunk for this entry with the given outcome.
        ///
        /// - Parameter outcome: The outcome to resume the continuation with.
        /// - Returns: A resumption thunk to execute after releasing the lock.
        @inlinable
        public func resumption(with outcome: Outcome) -> Async.Waiter.Resumption {
            let cont = self.continuation
            return Async.Waiter.Resumption {
                cont.resume(returning: outcome)
            }
        }
    }
}

// MARK: - Enqueue

extension Async.Waiter.Queue {
    /// Enqueues a waiter at the back of the queue.
    ///
    /// **Must be called under lock.**
    ///
    /// - Parameter entry: The waiter entry to enqueue.
    @inlinable
    public func enqueue(_ entry: Entry) {
        _entries.push.back(entry)
    }
}

// MARK: - Dequeue Operations

extension Async.Waiter.Queue {
    /// Dequeues the first waiter from the front (FIFO).
    ///
    /// **Must be called under lock.**
    ///
    /// Returns the waiter regardless of flag state. Use `dequeueEligible`
    /// to handle flagged waiters automatically.
    ///
    /// - Returns: The first waiter, or nil if queue is empty.
    @inlinable
    public func dequeueFirst() -> Entry? {
        try? _entries.pop.front()
    }

    /// Dequeues the first eligible (non-flagged) waiter.
    ///
    /// **Must be called under lock.**
    ///
    /// Pops entries from the front until a non-flagged entry is found.
    /// Flagged entries encountered are dequeued and their resumptions
    /// appended to `pending` using the provided outcome closure.
    ///
    /// **Side effect:** This method dequeues flagged entries from the front
    /// of the queue and appends their resumptions to `pending`. This prevents
    /// accumulation of dead waiters while completing them properly.
    ///
    /// - Parameters:
    ///   - pending: Array to append resumptions for flagged entries.
    ///              Not cleared; resumptions are appended.
    ///   - outcome: Closure that determines the outcome for flagged entries.
    ///              Receives the flag reason and entry.
    /// - Returns: The first eligible waiter, or nil if none found.
    @inlinable
    public func dequeueEligible(
        into pending: inout [Async.Waiter.Resumption],
        outcome: (Async.Waiter.Flag.Reason, Entry) -> Outcome
    ) -> Entry? {
        while let entry = try? _entries.pop.front() {
            if let reason = entry.flag.reason {
                // Flagged - prepare resumption and continue
                pending.append(entry.resumption(with: outcome(reason, entry)))
            } else {
                // Found eligible entry
                return entry
            }
        }
        return nil
    }
}

// MARK: - Reap Operations

extension Async.Waiter.Queue {
    /// Reaps all flagged waiters via scan+rebuild.
    ///
    /// **Must be called under lock.**
    ///
    /// Drains the queue, keeping survivors (non-flagged entries) in a new
    /// queue, and prepares resumptions for flagged entries.
    ///
    /// - Parameters:
    ///   - pending: Array to append resumptions for flagged entries.
    ///              Not cleared; resumptions are appended.
    ///   - outcome: Closure that determines the outcome for flagged entries.
    ///              Receives the flag reason and entry.
    @inlinable
    public func reapFlagged(
        into pending: inout [Async.Waiter.Resumption],
        outcome: (Async.Waiter.Flag.Reason, Entry) -> Outcome
    ) {
        var survivors = Deque<Entry>()
        while let entry = try? _entries.pop.front() {
            if let reason = entry.flag.reason {
                pending.append(entry.resumption(with: outcome(reason, entry)))
            } else {
                survivors.push.back(entry)
            }
        }
        _entries = survivors
    }

    /// Reaps all waiters (flagged or not), preparing resumptions.
    ///
    /// **Must be called under lock.**
    ///
    /// Use this for shutdown scenarios where all waiters must be woken
    /// regardless of flag state.
    ///
    /// - Parameters:
    ///   - pending: Array to append resumptions.
    ///              Not cleared; resumptions are appended.
    ///   - outcome: Closure that determines the outcome for each entry.
    @inlinable
    public func reapAll(
        into pending: inout [Async.Waiter.Resumption],
        outcome: (Entry) -> Outcome
    ) {
        while let entry = try? _entries.pop.front() {
            pending.append(entry.resumption(with: outcome(entry)))
        }
    }
}
