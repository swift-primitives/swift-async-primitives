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
    /// A bucket in the timer wheel containing an intrusive linked list of nodes.
    ///
    /// Each slot maintains head and tail pointers for O(1) append and O(1)
    /// removal (given the node's index). The list is doubly-linked via
    /// `prev`/`next` pointers stored in the nodes themselves.
    ///
    /// Slot is a data-only type. List operations are implemented as methods
    /// on `Wheel` that take `inout Slot`.
    @usableFromInline
    struct Slot: Sendable {
        /// Index of the first node, or nil if empty.
        @usableFromInline
        var head: Storage.Index?

        /// Index of the last node, or nil if empty.
        @usableFromInline
        var tail: Storage.Index?

        /// Number of nodes in this slot.
        @usableFromInline
        var count: Int

        /// Creates an empty slot.
        @usableFromInline
        init() {
            self.head = nil
            self.tail = nil
            self.count = 0
        }

        /// Whether this slot is empty.
        @usableFromInline
        var isEmpty: Bool { head == nil }
    }
}

// MARK: - Slot Access Helper

extension Async.Timer.Wheel {
    /// Executes a closure with mutable access to a specific slot.
    ///
    /// Uses `withUnsafeMutableBufferPointer` to obtain a stable `inout Slot`
    /// reference, avoiding repeated indexing and ensuring coherent mutation.
    ///
    /// - Parameters:
    ///   - level: The level index.
    ///   - slot: The slot index within the level.
    ///   - body: A closure that receives `inout Slot`.
    @usableFromInline
    mutating func withSlot<T>(level: Int, slot: Int, _ body: (inout Slot) -> T) -> T {
        unsafe levels[level].slots.withUnsafeMutableBufferPointer { buffer in
            unsafe body(&buffer[slot])
        }
    }
}

// MARK: - Intrusive List Operations

extension Async.Timer.Wheel {
    /// Appends a node to the tail of a slot's list.
    ///
    /// - Parameters:
    ///   - index: The typed index of the node to append.
    ///   - slot: The slot to append to.
    ///
    /// - Complexity: O(1)
    /// - Precondition: `storage[index]` must exist and have nil prev/next.
    @usableFromInline
    mutating func slotAppend(_ index: Storage.Index, to slot: inout Slot) {
        if let tailIndex = slot.tail {
            // Link to existing tail
            storage[tailIndex]?.next = index
            storage[index]?.prev = tailIndex
        } else {
            // First node
            slot.head = index
        }
        slot.tail = index
        storage[index]?.next = nil
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
    mutating func slotRemove(_ index: Storage.Index, from slot: inout Slot) {
        guard let node = storage[index] else { return }

        let prevIndex = node.prev
        let nextIndex = node.next

        // Update previous node's next pointer
        if let p = prevIndex {
            storage[p]?.next = nextIndex
        } else {
            // Removing head
            slot.head = nextIndex
        }

        // Update next node's prev pointer
        if let n = nextIndex {
            storage[n]?.prev = prevIndex
        } else {
            // Removing tail
            slot.tail = prevIndex
        }

        // Clear the removed node's links
        storage[index]?.prev = nil
        storage[index]?.next = nil

        slot.count -= 1
    }

    /// Removes and returns the first node's typed index from a slot.
    ///
    /// - Parameter slot: The slot to pop from.
    /// - Returns: The typed index of the removed node, or nil if empty.
    ///
    /// - Complexity: O(1)
    @usableFromInline
    mutating func slotPopFirst(from slot: inout Slot) -> Storage.Index? {
        guard let index = slot.head else { return nil }
        slotRemove(index, from: &slot)
        return index
    }
}
