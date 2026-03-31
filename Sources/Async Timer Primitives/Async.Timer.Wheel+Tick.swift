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

// MARK: - Tick Conversion

extension Async.Timer.Wheel {
    /// Converts an instant to a tick number relative to the wheel's epoch.
    ///
    /// - Parameter instant: The instant to convert.
    /// - Returns: The tick number. Returns 0 if the instant is before the epoch.
    ///
    /// - Complexity: O(1)
    @inlinable
    func tickNumber(for instant: C.Instant) -> Tick {
        let elapsed = start.duration(to: instant)
        return elapsed.dividedRoundingDown(by: config.tick)
    }

    /// Computes the current slot index at a given level.
    ///
    /// This is derived from the tick value using bit operations:
    /// ```
    /// slot = (tick >> (level * shift)) & mask
    /// ```
    ///
    /// - Parameter level: The level index (0-based).
    /// - Returns: The current slot index at that level.
    ///
    /// - Complexity: O(1)
    @inlinable
    func currentSlot(level: Int) -> Int {
        Int((tick >> Tick(level * config.slotShift)) & Tick(config.slotMask))
    }

    /// Finds the appropriate level for a timer with the given delta.
    ///
    /// Returns the smallest level L where the offset fits in one rotation:
    /// ```
    /// offset = delta >> (L * shift)
    /// condition: offset < slots
    /// ```
    ///
    /// - Parameter delta: Ticks until the timer fires.
    /// - Returns: The level index (0-based).
    ///
    /// - Complexity: O(levels), typically O(1) for near-term timers.
    @inlinable
    func level(for delta: Tick) -> Int {
        let shift = config.slotShift
        let slots = Tick(config.slots)

        for level in 0..<(config.levels - 1) {
            let offset = delta >> Tick(level * shift)
            if offset < slots {
                return level
            }
        }
        return config.levels - 1
    }

    /// Computes the slot index for a timer at a given level with the given delta.
    ///
    /// ```
    /// slot = (currentSlot(level) + offset) & mask
    /// where offset = delta >> (level * shift)
    /// ```
    ///
    /// - Parameters:
    ///   - level: The level index (0-based).
    ///   - delta: Ticks until the timer fires.
    /// - Returns: The slot index within the level.
    ///
    /// - Complexity: O(1)
    @inlinable
    func slot(for level: Int, delta: Tick) -> Int {
        let offset = delta >> Tick(level * config.slotShift)
        return (currentSlot(level: level) + Int(offset)) & config.slotMask
    }
}
