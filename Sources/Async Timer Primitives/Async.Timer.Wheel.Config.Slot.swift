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

extension Async.Timer.Wheel.Config {
    /// Namespace accessor for slot-derived constants.
    public struct Slot: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }
    }
}

// MARK: - Computed Properties

extension Async.Timer.Wheel.Config.Slot {
    /// Bit mask for slot index computation: `slots - 1`.
    @inlinable
    public var mask: Int { config.slots - 1 }

    /// Bit shift for level computation: `log2(slots)`.
    @inlinable
    public var shift: Int { config.slots.trailingZeroBitCount }
}
