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
    /// Configuration for a timer wheel.
    ///
    /// ## Parameters
    ///
    /// - `tick`: Duration of one tick at level 0. Determines timing precision.
    /// - `slots`: Number of slots per level. Must be a power of two.
    /// - `levels`: Number of hierarchical levels (1...8).
    /// - `capacity`: Maximum number of concurrent timers.
    ///
    /// ## Range
    ///
    /// The wheel can schedule timers up to `range` in the future:
    /// ```
    /// range = tick × slots^levels
    /// ```
    ///
    /// With default config (1ms tick, 64 slots, 6 levels):
    /// - Range = 1ms × 64^6 ≈ 2.18 years
    ///
    /// ## Memory
    ///
    /// Memory usage is approximately:
    /// ```
    /// (slots × levels × 24 bytes) + (capacity × 48 bytes)
    /// ```
    ///
    /// With default config and 10,000 capacity: ~490 KB
    public struct Config: Sendable, Hashable {
        /// Duration of one tick at level 0.
        public let tick: Duration

        /// Number of slots per level. Must be a power of two.
        public let slots: Int

        /// Number of hierarchical levels.
        public let levels: Int

        /// Maximum number of concurrent timers.
        public let capacity: Int

        /// Creates a wheel configuration.
        ///
        /// - Parameters:
        ///   - tick: Duration of one tick. Must be positive.
        ///   - slots: Slots per level. Must be a power of two, at least 2.
        ///   - levels: Number of levels. Must be 1...8.
        ///   - capacity: Maximum concurrent timers. Must be positive.
        ///
        /// - Precondition: `slots` must be a power of two.
        /// - Precondition: `levels` must be in range 1...8.
        /// - Precondition: `capacity` must be positive.
        public init(tick: Duration, slots: Int, levels: Int, capacity: Int) {
            precondition(tick > .zero, "tick must be positive")
            precondition(slots >= 2, "slots must be at least 2")
            precondition(slots & (slots - 1) == 0, "slots must be a power of two")
            precondition(levels >= 1 && levels <= 8, "levels must be 1...8")
            precondition(capacity > 0, "capacity must be positive")

            self.tick = tick
            self.slots = slots
            self.levels = levels
            self.capacity = capacity
        }
    }
}

// MARK: - Default Configuration

extension Async.Timer.Wheel.Config {
    /// Default configuration suitable for most applications.
    ///
    /// - tick: 1 millisecond
    /// - slots: 64 (power of two)
    /// - levels: 6
    /// - capacity: 65536
    ///
    /// This provides:
    /// - Range: ~2.18 years
    /// - Precision: 1ms
    /// - Memory: ~3 MB at full capacity
    public static var `default`: Self {
        Self(
            tick: .milliseconds(1),
            slots: 64,
            levels: 6,
            capacity: 65536
        )
    }
}

// MARK: - Slot Accessor

extension Async.Timer.Wheel.Config {
    /// Namespace accessor for slot-derived constants.
    public struct Slot: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }

        /// Bit mask for slot index computation: `slots - 1`.
        @inlinable
        public var mask: Int { config.slots - 1 }

        /// Bit shift for level computation: `log2(slots)`.
        @inlinable
        public var shift: Int { config.slots.trailingZeroBitCount }
    }

    /// Slot-derived constants.
    @inlinable
    public var slot: Slot { Slot(config: self) }
}

// MARK: - Range Accessor

extension Async.Timer.Wheel.Config {
    /// Namespace accessor for range-derived constants.
    public struct Range: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }

        /// Maximum representable ticks: `slots^levels`.
        ///
        /// Timers with deadlines beyond this range from the current tick
        /// cannot be scheduled and will return `nil` from `schedule()`.
        @inlinable
        public var ticks: UInt64 {
            UInt64(1) << UInt64(config.levels * config.slot.shift)
        }
    }

    /// Range-derived constants.
    @inlinable
    public var range: Range { Range(config: self) }

    /// Maximum schedulable duration into the future.
    ///
    /// This is `tick × range.ticks`. Timers beyond this duration
    /// cannot be scheduled.
    public var duration: Duration {
        // Compute carefully to avoid overflow
        // range.ticks can be very large (64^6 = 68 billion)
        // We compute: tick * range.ticks
        let (seconds, attoseconds) = tick.components
        let tickAttos = Int64(seconds) * 1_000_000_000_000_000_000 + attoseconds

        // For very large range.ticks, we may overflow. Cap at Duration.max equivalent.
        let maxAttos = Int64.max
        let rangeTicksI64 = Int64(clamping: range.ticks)

        // Check for overflow before multiplying
        if rangeTicksI64 > 0 && tickAttos > maxAttos / rangeTicksI64 {
            // Would overflow, return max representable
            return .seconds(Int64.max / 1_000_000_000)
        }

        let totalAttos = tickAttos * rangeTicksI64
        let rangeSeconds = totalAttos / 1_000_000_000_000_000_000
        let rangeAttos = totalAttos % 1_000_000_000_000_000_000

        return .seconds(rangeSeconds) + .nanoseconds(rangeAttos / 1_000_000_000)
    }
}

// MARK: - Level Accessor

extension Async.Timer.Wheel.Config {
    /// Namespace accessor for level-derived computations.
    public struct Level: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }

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

    /// Level-derived computations.
    @inlinable
    public var level: Level { Level(config: self) }
}

// MARK: - Ticks Accessor

extension Async.Timer.Wheel.Config {
    /// Namespace accessor for tick-derived computations.
    public struct Ticks: Sendable {
        @usableFromInline let config: Async.Timer.Wheel<C>.Config

        @usableFromInline
        init(config: Async.Timer.Wheel<C>.Config) {
            self.config = config
        }

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

    /// Tick-derived computations.
    @inlinable
    public var ticks: Ticks { Ticks(config: self) }
}
