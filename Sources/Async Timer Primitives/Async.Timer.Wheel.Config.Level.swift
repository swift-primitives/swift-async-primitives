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
    /// Namespace accessor for level-derived computations.
    public struct Level: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }
    }
}

// MARK: - Computed Properties

extension Async.Timer.Wheel.Config.Level {
    /// Returns the tick range covered by a specific level.
    ///
    /// Level 0 covers ticks 0..<slots.
    /// Level 1 covers ticks 0..<(slots^2).
    /// And so on.
    ///
    /// - Parameter level: The level index (0-based).
    /// - Returns: The number of ticks representable at this level.
    @inlinable
    public func range(_ level: Int) -> UInt64 {
        precondition(level >= 0 && level < config.levels, "level out of range")
        return UInt64(1) << UInt64((level + 1) * config.slot.shift)
    }
}
