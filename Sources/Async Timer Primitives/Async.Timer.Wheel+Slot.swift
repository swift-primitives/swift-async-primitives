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

// MARK: - Link Topology Operations (delegated to Buffer.Link)

extension Async.Timer.Wheel {

    /// Provides stable `inout` access to a level's slot header.
    @usableFromInline
    mutating func withSlot<T>(
        level: Int,
        slot: Int,
        _ body: (inout Buffer<Payload>.Linked<2>.Header) -> T
    ) -> T {
        unsafe levels[level].slots.withUnsafeMutableBufferPointer { buffer in
            unsafe body(&buffer[slot])
        }
    }

    /// Appends a node to the tail of a slot's list.
    ///
    /// - Complexity: O(1)
    @usableFromInline
    mutating func append(_ index: Index<Node>, to header: inout Buffer<Payload>.Linked<2>.Header) {
        unsafe Buffer<Payload>.Link<2>.append(index, header: &header) { idx in
            unsafe self.storage.pointer(at: idx)
        }
    }

    /// Removes a node from a slot's list.
    ///
    /// - Complexity: O(1)
    /// - Precondition: The node must be in this slot's list.
    @usableFromInline
    mutating func remove(_ index: Index<Node>, from header: inout Buffer<Payload>.Linked<2>.Header) {
        unsafe Buffer<Payload>.Link<2>.unlink(index, header: &header) { idx in
            unsafe self.storage.pointer(at: idx)
        }
    }

    /// Removes and returns the first node's index from a slot.
    ///
    /// - Returns: The index of the removed node, or nil if empty.
    /// - Complexity: O(1)
    @usableFromInline
    mutating func popFirst(from header: inout Buffer<Payload>.Linked<2>.Header) -> Index<Node>? {
        unsafe Buffer<Payload>.Link<2>.unlinkFirst(header: &header) { idx in
            unsafe self.storage.pointer(at: idx)
        }
    }
}
