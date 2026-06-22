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

public import Index_Primitives

extension Async.Timer {
    /// Hierarchical timer wheel with O(1) amortized operations.
    ///
    /// A timer wheel is a data structure for efficient time-based scheduling,
    /// providing O(1) insertion, cancellation, and per-tick advancement.
    ///
    /// ## Design
    ///
    /// The wheel uses multiple levels of slots with increasing granularity:
    /// - Level 0: finest resolution (e.g., 1ms per slot)
    /// - Level N: coarser resolution (slots^N times level 0)
    ///
    /// Timers cascade from higher levels to lower levels as time advances,
    /// eventually firing from level 0.
    ///
    /// ## Usage
    ///
    /// The wheel is a mutable struct intended for use within a single actor:
    ///
    /// ```swift
    /// actor TimerService {
    ///     var wheel: Async.Timer.Wheel<ContinuousClock>
    ///
    ///     init() {
    ///         wheel = Wheel(clock: ContinuousClock())
    ///     }
    ///
    ///     func scheduleTimeout(deadline: ContinuousClock.Instant) -> Wheel.ID? {
    ///         wheel.schedule(deadline: deadline)
    ///     }
    /// }
    /// ```
    ///
    /// ## Invariants
    ///
    /// - Each scheduled timer fires exactly once or is explicitly cancelled
    /// - Timers fire at or after their deadline (within tick granularity)
    /// - Memory is bounded by capacity; no allocation after initialization
    ///
    /// ## Precision
    ///
    /// Timer firing precision is bounded by the tick duration. A timer may
    /// fire up to one tick after its deadline.
    ///
    /// ## Clock Requirement
    ///
    /// The wheel assumes monotonically non-decreasing time. Successive calls
    /// to `advance(to:)` should pass non-decreasing instants. If time moves
    /// backward, the advance is a no-op.
    public struct Wheel<C: Clock>: ~Copyable, Sendable where C.Duration == Duration {
        /// Configuration for this wheel.
        public let config: Config

        /// Epoch anchor captured at initialization.
        @usableFromInline
        let start: C.Instant

        /// Current tick (time since start in tick units).
        @usableFromInline
        var tick: Tick

        /// Per-level slot arrays.
        @usableFromInline
        var levels: [Level]

        /// Slab storage for timer entries.
        @usableFromInline
        var storage: Storage

        /// Number of live timers.
        @usableFromInline
        var _count: Int

        /// Cached index of the earliest timer (lazy invalidation).
        @usableFromInline
        var earliest: Index<Node>?

        /// Creates a timer wheel with the specified clock and configuration.
        ///
        /// - Parameters:
        ///   - clock: The clock to use for time calculations.
        ///   - config: Wheel configuration. Defaults to `.default`.
        public init(clock: C, config: Config = .default) {
            self.config = config
            self.start = clock.now
            self.tick = 0
            self.storage = Storage(capacity: config.capacity)
            let sentinel = storage.sentinel
            self.levels = (0..<config.levels).map { _ in
                Level(slotCount: config.slots, sentinel: sentinel)
            }
            self._count = 0
            self.earliest = nil
        }
    }
}

// MARK: - Public API

extension Async.Timer.Wheel {
    /// The number of live (scheduled, not-yet-fired) timers.
    @inlinable
    public var count: Int { _count }

    /// Whether the wheel has no scheduled timers.
    @inlinable
    public var isEmpty: Bool { _count == 0 }
}
