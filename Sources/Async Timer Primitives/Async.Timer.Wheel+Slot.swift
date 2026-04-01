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

// MARK: - Intrusive List Operations

extension Async.Timer.Wheel {
    /// Appends a node to the tail of a slot's list.
    ///
    /// - Parameters:
    ///   - index: The typed index of the node to append.
    ///   - slot: The slot to append to.
    ///
    /// - Complexity: O(1)
    /// - Precondition: The node at `index` must be occupied with nil prev/next.
    @usableFromInline
    mutating func append(_ index: Index<Node>, to slot: inout Slot) {
        if let tailIndex = slot.tail {
            // Link to existing tail
            unsafe storage.pointer(at: tailIndex).pointee.next = index
            unsafe storage.pointer(at: index).pointee.prev = tailIndex
        } else {
            // First node
            slot.head = index
        }
        slot.tail = index
        unsafe storage.pointer(at: index).pointee.next = nil
        slot.count += 1
    }

    /// Removes a node from a slot's list.
    ///
    /// - Parameters:
    ///   - index: The typed index of the node to remove.
    ///   - slot: The slot to remove from.
    ///
    /// - Complexity: O(1)
    /// - Precondition: The node must be in this slot's list.
    @usableFromInline
    mutating func remove(_ index: Index<Node>, from slot: inout Slot) {
        let nodePtr = unsafe storage.pointer(at: index)
        let prevIndex = unsafe nodePtr.pointee.prev
        let nextIndex = unsafe nodePtr.pointee.next

        // Update previous node's next pointer
        if let p = prevIndex {
            unsafe storage.pointer(at: p).pointee.next = nextIndex
        } else {
            // Removing head
            slot.head = nextIndex
        }

        // Update next node's prev pointer
        if let n = nextIndex {
            unsafe storage.pointer(at: n).pointee.prev = prevIndex
        } else {
            // Removing tail
            slot.tail = prevIndex
        }

        // Clear the removed node's links
        unsafe nodePtr.pointee.prev = nil
        unsafe nodePtr.pointee.next = nil

        slot.count -= 1
    }

    /// Removes and returns the first node's typed index from a slot.
    ///
    /// - Parameter slot: The slot to pop from.
    /// - Returns: The typed index of the removed node, or nil if empty.
    ///
    /// - Complexity: O(1)
    @usableFromInline
    mutating func popFirst(from slot: inout Slot) -> Index<Node>? {
        guard let index = slot.head else { return nil }
        remove(index, from: &slot)
        return index
    }
}
