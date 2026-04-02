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

extension Async.Timer.Wheel {
    /// A single level in the hierarchical timer wheel.
    ///
    /// Each level contains a fixed-size array of slots. The "current" slot
    /// at each level is derived from the wheel's tick value using bit
    /// operations, so no separate current index is stored.
    ///
    /// ## Level Semantics
    ///
    /// - Level 0: Slots represent individual ticks (finest granularity)
    /// - Level N: Slots represent `slots^N` ticks each
    ///
    /// Timers cascade from higher levels to lower levels as time advances.
    @usableFromInline
    struct Level: Sendable {
        /// The slot headers in this level — one linked list per slot.
        @usableFromInline
        var slots: [Link<2>.Header<Node>]

        /// Creates a level with the specified number of slots.
        ///
        /// - Parameters:
        ///   - slotCount: The number of slots (must match config.slots).
        ///   - sentinel: The sentinel value for linked list headers.
        @usableFromInline
        init(slotCount: Int, sentinel: Index<Node>) {
            self.slots = [Link<2>.Header<Node>](
                repeating: Link<2>.Header<Node>(sentinel: sentinel),
                count: slotCount
            )
        }
    }
}
