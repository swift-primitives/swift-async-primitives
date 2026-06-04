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
public import Buffer_Arena_Primitive
public import Buffer_Arena_Bounded_Primitive

extension Async.Timer.Wheel {
    /// Arena-backed storage for timer nodes.
    ///
    /// Storage provides O(1) allocation and deallocation of node slots
    /// using `Buffer.Arena.Bounded` — a fixed-capacity arena with per-slot
    /// generation tokens and a LIFO free list.
    ///
    /// ## Thread Safety
    ///
    /// Storage is marked `@unchecked Sendable` because it contains mutable
    /// state. Safety is guaranteed by the wheel's design: the wheel is
    /// `~Copyable` and intended for single-actor use. All mutations are
    /// serialized by the owning actor.
    ///
    /// ## Generation Tokens
    ///
    /// Each slot has an independent generation token (odd = occupied,
    /// even = free). When a slot is reused, its token increments. This
    /// prevents the ABA problem where a stale ID might accidentally match
    /// a new timer. Per-slot tokens provide stronger ABA protection than
    /// a global counter — they wrap only after 2^32 reuses of the same slot.
    @usableFromInline
    struct Storage: ~Copyable, @unchecked Sendable {
        /// Arena buffer managing node allocation and lifecycle.
        @usableFromInline
        var arena: Buffer<Storage<Node>.Arena>.Arena.Bounded

        /// Sentinel value for linked list headers (derived from arena capacity).
        @usableFromInline
        let sentinel: Index<Node>

        /// Creates storage with the specified capacity.
        ///
        /// - Parameter capacity: Maximum number of concurrent timers.
        @usableFromInline
        init(capacity: Int) {
            let count = Index<Node>.Count(Cardinal(UInt(capacity)))
            self.arena = .init(minimumCapacity: count)
            self.sentinel = Index<Node>(Ordinal(UInt(capacity)))
        }
    }
}

// MARK: - Allocation

extension Async.Timer.Wheel.Storage {

    /// Inserts a node into the arena.
    ///
    /// - Parameter node: The node to store.
    /// - Returns: The arena position handle, or nil if capacity is exhausted.
    ///
    /// - Complexity: O(1)
    @usableFromInline
    mutating func insert(
        _ node: consuming Async.Timer.Wheel<C>.Node
    ) -> Buffer<Storage<Async.Timer.Wheel<C>.Node>.Arena>.Arena.Position? {
        try? arena.insert(node)
    }

    /// Frees the slot at the given index, deinitializing the node.
    ///
    /// - Parameter index: The slot index to free.
    ///
    /// - Complexity: O(1)
    /// - Precondition: The slot must be currently occupied.
    @usableFromInline
    mutating func free(at index: Index<Async.Timer.Wheel<C>.Node>) {
        arena.free(at: index)
    }
}

// MARK: - Access

extension Async.Timer.Wheel.Storage {

    /// Returns whether the given position handle is still valid.
    ///
    /// A position is valid when its token matches the slot's current
    /// generation token and the slot is occupied.
    @usableFromInline
    func isValid(
        _ position: Buffer<Storage<Async.Timer.Wheel<C>.Node>.Arena>.Arena.Position
    ) -> Bool {
        arena.isValid(position)
    }
}
