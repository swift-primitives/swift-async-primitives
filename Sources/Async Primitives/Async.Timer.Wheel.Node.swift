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

extension Async.Timer.Wheel {
    /// Internal node representing a scheduled timer in storage.
    ///
    /// Nodes are stored in a slab allocator and linked into intrusive
    /// doubly-linked lists within slots. Each node contains:
    /// - Timer metadata (ID, deadline)
    /// - Position tracking (level, slot)
    /// - Intrusive list pointers (prev, next)
    @usableFromInline
    struct Node: Sendable {
        /// The timer's unique identifier.
        @usableFromInline
        var id: ID

        /// The original deadline instant (for yielding in Entry).
        @usableFromInline
        var deadline: C.Instant

        /// The deadline as a tick number (for internal calculations).
        @usableFromInline
        var deadlineTick: Tick

        /// The level this node is currently in.
        @usableFromInline
        var level: UInt8

        /// The slot this node is currently in.
        @usableFromInline
        var slot: UInt16

        /// Previous node in the slot's linked list (nil if head).
        @usableFromInline
        var prev: UInt32?

        /// Next node in the slot's linked list (nil if tail).
        @usableFromInline
        var next: UInt32?

        /// Creates a node with the given parameters.
        @usableFromInline
        init(
            id: ID,
            deadline: C.Instant,
            deadlineTick: Tick,
            level: Int,
            slot: Int
        ) {
            self.id = id
            self.deadline = deadline
            self.deadlineTick = deadlineTick
            self.level = UInt8(level)
            self.slot = UInt16(slot)
            self.prev = nil
            self.next = nil
        }
    }
}
