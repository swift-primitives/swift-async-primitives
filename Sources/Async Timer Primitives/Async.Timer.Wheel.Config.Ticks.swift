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
    /// Namespace accessor for tick-derived computations.
    public struct Ticks: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }
    }
}

// MARK: - Computed Properties

extension Async.Timer.Wheel.Config.Ticks {
    /// Returns the tick span per slot at a specific level.
    ///
    /// Level 0: 1 tick per slot.
    /// Level 1: `slots` ticks per slot.
    /// Level N: `slots^N` ticks per slot.
    ///
    /// - Parameter level: The level index (0-based).
    /// - Returns: The number of ticks each slot represents.
    @inlinable
    public func perSlot(_ level: Int) -> UInt64 {
        precondition(level >= 0 && level < config.levels, "level out of range")
        return UInt64(1) << UInt64(level * config.slot.shift)
    }
}
