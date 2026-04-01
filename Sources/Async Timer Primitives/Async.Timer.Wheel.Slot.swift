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
    /// List operations (`append`, `remove`, `popFirst`) are methods on `Wheel`
    /// taking `inout Slot` — `Node` and `Storage` are sibling types only
    /// resolvable in the `Wheel<C>` generic context.
    @usableFromInline
    struct Slot: Sendable {
        /// Index of the first node, or nil if empty.
        @usableFromInline
        var head: Index<Node>?

        /// Index of the last node, or nil if empty.
        @usableFromInline
        var tail: Index<Node>?

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
    }
}

// MARK: - Computed Properties

extension Async.Timer.Wheel.Slot {
    /// Whether this slot is empty.
    @usableFromInline
    var isEmpty: Bool { head == nil }
}


