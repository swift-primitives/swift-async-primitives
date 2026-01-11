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

import Buffer_Primitives

extension Async.Waiter.Queue {
    /// A drainable collection of ~Copyable elements.
    ///
    /// Used to return collections of flagged entries from queue operations.
    /// Elements can only be accessed by consuming them via `popFront()` or `drain()`.
    ///
    /// ## Design
    ///
    /// - Backed by `Buffer.Ring.Unbounded` for efficient FIFO access
    /// - ~Copyable to prevent accidental duplication
    /// - No indexed access - elements must be consumed in order
    ///
    /// ## Usage
    ///
    /// ```swift
    /// var flagged = Drain<Flagged<Outcome, Metadata>>()
    /// queue.popEligible(flaggedInto: &flagged)
    ///
    /// // Outside lock: process flagged entries
    /// flagged.drain { entry in
    ///     let resumption = entry.resumption(with: computeOutcome(entry.reason))
    ///     resumption.resume()
    /// }
    /// ```
    public struct Drain<Element: ~Copyable>: ~Copyable {
        @usableFromInline
        var _storage: Buffer.Ring.Unbounded<Element>

        /// Creates an empty drain.
        @inlinable
        public init() {
            self._storage = Buffer.Ring.Unbounded<Element>(minimumCapacity: 4)
        }

        /// The number of elements in the drain.
        @inlinable
        public var count: Int { _storage.count }

        /// Whether the drain is empty.
        @inlinable
        public var isEmpty: Bool { _storage.isEmpty }
    }
}

// MARK: - Append

extension Async.Waiter.Queue.Drain where Element: ~Copyable {
    /// Appends an element to the drain.
    ///
    /// - Parameter element: The element to append (ownership transferred).
    @inlinable
    public mutating func append(_ element: consuming Element) {
        _storage.push(element)
    }
}

// MARK: - Pop

extension Async.Waiter.Queue.Drain where Element: ~Copyable {
    /// Pops the first element from the drain.
    ///
    /// - Returns: The first element, or `nil` if empty.
    @inlinable
    public mutating func popFront() -> Element? {
        _storage.popFront()
    }
}

// MARK: - Drain

extension Async.Waiter.Queue.Drain where Element: ~Copyable {
    /// Drains all elements, consuming each via the closure.
    ///
    /// The drain is empty after this call.
    ///
    /// - Parameter body: A closure that consumes each element.
    @inlinable
    public mutating func drain(_ body: (consuming Element) -> Void) {
        _storage.drain(body)
    }
}

// MARK: - Sendable

extension Async.Waiter.Queue.Drain: @unchecked Sendable where Element: Sendable {}
