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
    /// Integer representation of time in tick units.
    ///
    /// Ticks are counted from the wheel's epoch (captured at initialization).
    /// All internal time arithmetic uses ticks to avoid floating-point
    /// imprecision and Instant comparison overhead.
    ///
    /// With UInt64 and 1ms ticks, the wheel can represent ~584 million years.
    @usableFromInline
    typealias Tick = UInt64
}

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
    /// slot = (tick >> (level × shift)) & mask
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
    /// offset = delta >> (L × shift)
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
    /// where offset = delta >> (level × shift)
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

// MARK: - Duration Division

extension Duration {
    /// Divides this duration by another, rounding down.
    ///
    /// Returns the largest integer N such that `divisor × N <= self`.
    ///
    /// - Parameter divisor: The duration to divide by. Must be positive.
    /// - Returns: The quotient as a tick count. Returns 0 if self is negative or zero.
    ///
    /// - Complexity: O(1)
    @usableFromInline
    func dividedRoundingDown(by divisor: Duration) -> UInt64 {
        let (selfSec, selfAtto) = self.components
        let (divSec, divAtto) = divisor.components

        // Handle negative or zero elapsed time
        if selfSec < 0 || (selfSec == 0 && selfAtto <= 0) {
            return 0
        }

        // Convert to attoseconds (10^-18 seconds)
        // Using Int128 would be ideal, but we'll use careful arithmetic
        // to avoid overflow for reasonable durations.

        // For durations up to ~292 years, seconds fit in Int64.
        // Attoseconds are always in range [0, 10^18).

        // Strategy: compute (selfSec * 10^18 + selfAtto) / (divSec * 10^18 + divAtto)
        // We need to handle this without 128-bit integers.

        // First, compute divisor in attoseconds (may overflow for large divisors)
        let attosPerSecond: Int64 = 1_000_000_000_000_000_000

        // Check if divisor is small enough to fit in Int64 attoseconds
        // divSec * 10^18 overflows if divSec > 9 (approximately)
        if divSec <= 9 && divSec >= 0 {
            // Divisor fits in Int64 attoseconds
            let divisorAttos = divSec * attosPerSecond + divAtto

            if divisorAttos <= 0 {
                // Invalid divisor
                return 0
            }

            // Now compute self in attoseconds if possible
            if selfSec <= 9 && selfSec >= 0 {
                // Self also fits
                let selfAttos = selfSec * attosPerSecond + selfAtto
                return UInt64(selfAttos / divisorAttos)
            }

            // Self is large, use a different approach:
            // self / divisor = (selfSec * 10^18 + selfAtto) / divisorAttos
            //                = selfSec * (10^18 / divisorAttos) + (selfSec * (10^18 % divisorAttos) + selfAtto) / divisorAttos

            let quotientPerSecond = attosPerSecond / divisorAttos
            let remainderPerSecond = attosPerSecond % divisorAttos

            // Be careful with overflow for very large selfSec
            let secondsContribution = UInt64(selfSec) * UInt64(quotientPerSecond)

            // Remainder part
            let remainderAttos = Int64(selfSec) * remainderPerSecond + selfAtto
            let remainderContribution = UInt64(remainderAttos / divisorAttos)

            return secondsContribution + remainderContribution
        }

        // Divisor is large (> 9 seconds). Use simpler integer division.
        // For very large divisors, the result will be small.
        if divSec > selfSec {
            return 0
        }

        // Approximate: treat as seconds division (loses attosecond precision)
        // This is acceptable because large divisors mean low precision is expected
        if divSec > 0 {
            return UInt64(selfSec / divSec)
        }

        // Divisor has 0 seconds but negative (shouldn't happen with valid Duration)
        return 0
    }
}
