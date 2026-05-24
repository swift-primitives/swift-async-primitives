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
public import Link_Primitives

extension Async.Timer.Wheel {
    /// Payload stored in each timer node.
    ///
    /// Contains timer metadata (ID, deadline) and position tracking
    /// (level, slot). Linked list pointers are managed by
    /// `Buffer.Linked.Node`'s `links` field.
    @usableFromInline
    struct Payload: Sendable {
        /// The timer's unique identifier.
        @usableFromInline
        var id: ID

        /// The timer's deadline (instant + tick representation).
        @usableFromInline
        var deadline: Deadline

        /// The level this node is currently in.
        @usableFromInline
        var level: UInt8

        /// The slot this node is currently in.
        @usableFromInline
        var slot: UInt16

        /// Creates a payload with the given parameters.
        @usableFromInline
        init(
            id: ID,
            deadline: Deadline,
            level: Int,
            slot: Int
        ) {
            self.id = id
            self.deadline = deadline
            self.level = UInt8(level)
            self.slot = UInt16(slot)
        }
    }

    /// A timer node: payload + doubly-linked list pointers.
    ///
    /// Uses `Link<2>.Node<Payload>` to embed `links: InlineArray<2, Index<Node>>`
    /// alongside the payload, enabling `Link<2>` topology operations.
    @usableFromInline
    typealias Node = Link<2>.Node<Payload>
}
