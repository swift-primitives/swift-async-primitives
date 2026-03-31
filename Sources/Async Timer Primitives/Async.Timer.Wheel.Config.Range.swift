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
    /// Namespace accessor for range-derived constants.
    public struct Range: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }
    }
}

// MARK: - Computed Properties

extension Async.Timer.Wheel.Config.Range {
    /// Maximum representable ticks: `slots^levels`.
    ///
    /// Timers with deadlines beyond this range from the current tick
    /// cannot be scheduled and will return `nil` from `schedule()`.
    @inlinable
    public var ticks: UInt64 {
        UInt64(1) << UInt64(config.levels * config.slot.shift)
    }
}
