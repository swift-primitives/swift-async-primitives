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

import Async_Primitives_Test_Support
import Testing

// MARK: - Test Suites

enum Timer {
    enum Wheel {
        enum Test {
            @Suite struct Unit {}
            @Suite struct EdgeCase {}
        }
    }
}

// MARK: - Unit Tests

extension Timer.Wheel.Test.Unit {
    @Test
    func `default config has expected values`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config.default
        #expect(config.tick == .milliseconds(1))
        #expect(config.slots == 64)
        #expect(config.levels == 6)
        #expect(config.capacity == 65536)
    }

    @Test
    func `config stores custom values`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(10),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        #expect(config.tick == .milliseconds(10))
        #expect(config.slots == 8)
        #expect(config.levels == 3)
        #expect(config.capacity == 100)
    }

    @Test
    func `slotMask is slots minus one`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 16, levels: 2, capacity: 100
        )
        #expect(config.slotMask == 15)
    }

    @Test
    func `slotShift is log2 of slots`() {
        let config8 = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 2, capacity: 100
        )
        #expect(config8.slotShift == 3)

        let config64 = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 64, levels: 2, capacity: 100
        )
        #expect(config64.slotShift == 6)
    }

    @Test
    func `rangeTicks is slots to the power of levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 3, capacity: 100
        )
        // 8^3 = 512; computed as 1 << (3 * 3) = 1 << 9 = 512
        #expect(config.rangeTicks == 512)
    }

    @Test
    func `levelRange returns cumulative range per level`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 3, capacity: 100
        )
        // Level 0: 1 << (1*3) = 8
        #expect(config.levelRange(0) == 8)
        // Level 1: 1 << (2*3) = 64
        #expect(config.levelRange(1) == 64)
        // Level 2: 1 << (3*3) = 512
        #expect(config.levelRange(2) == 512)
    }

    @Test
    func `ticksPerSlot returns ticks per slot at each level`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 3, capacity: 100
        )
        // Level 0: 1 tick per slot
        #expect(config.ticksPerSlot(0) == 1)
        // Level 1: 8 ticks per slot
        #expect(config.ticksPerSlot(1) == 8)
        // Level 2: 64 ticks per slot
        #expect(config.ticksPerSlot(2) == 64)
    }

    @Test
    func `range computes maximum schedulable duration`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(10), slots: 8, levels: 3, capacity: 100
        )
        // 512 ticks × 10ms per tick = 5.12 seconds
        let range = config.range
        #expect(range >= .seconds(5))
        #expect(range <= .seconds(6))
    }

    @Test
    func `default config rangeTicks is 64 to the 6th`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config.default
        // 64^6 = 2^36 = 68,719,476,736
        #expect(config.rangeTicks == 68_719_476_736)
    }

    // Note: Wheel is ~Copyable. Property accesses must be extracted to
    // Copyable locals before passing to #expect.

    @Test
    func `wheel init creates empty wheel`() {
        let wheel = Async.Timer.Wheel(clock: ContinuousClock())
        let count = wheel.count
        let isEmpty = wheel.isEmpty
        #expect(count == 0)
        #expect(isEmpty)
    }

    @Test
    func `wheel stores provided config`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(5), slots: 16, levels: 4, capacity: 256
        )
        let wheel = Async.Timer.Wheel(clock: ContinuousClock(), config: config)
        let wheelConfig = wheel.config
        #expect(wheelConfig == config)
    }

    @Test
    func `wheel uses default config when none provided`() {
        let wheel = Async.Timer.Wheel(clock: ContinuousClock())
        let wheelConfig = wheel.config
        #expect(wheelConfig == .default)
    }

    @Test
    func `config is Equatable and Hashable`() {
        let a = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 3, capacity: 100
        )
        let b = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 3, capacity: 100
        )
        let c = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(2), slots: 8, levels: 3, capacity: 100
        )
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - Edge Cases

extension Timer.Wheel.Test.EdgeCase {
    @Test
    func `config with minimum parameters`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .nanoseconds(1), slots: 2, levels: 1, capacity: 1
        )
        #expect(config.slotMask == 1)
        #expect(config.slotShift == 1)
        #expect(config.rangeTicks == 2)
        #expect(config.levelRange(0) == 2)
        #expect(config.ticksPerSlot(0) == 1)
    }

    @Test
    func `config with maximum levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 4, levels: 8, capacity: 100
        )
        // 4^8 = 2^16 = 65536
        #expect(config.rangeTicks == 65536)
    }

    @Test
    func `config with large slot count`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 256, levels: 2, capacity: 100
        )
        #expect(config.slotMask == 255)
        #expect(config.slotShift == 8)
        // 256^2 = 65536
        #expect(config.rangeTicks == 65536)
    }

    @Test
    func `ticksPerSlot increases geometrically across levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 4, capacity: 100
        )
        for level in 1..<config.levels {
            #expect(
                config.ticksPerSlot(level) == config.ticksPerSlot(level - 1) * UInt64(config.slots)
            )
        }
    }

    @Test
    func `levelRange increases geometrically across levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 16, levels: 4, capacity: 100
        )
        for level in 1..<config.levels {
            #expect(
                config.levelRange(level) == config.levelRange(level - 1) * UInt64(config.slots)
            )
        }
    }

    @Test
    func `highest level levelRange equals rangeTicks`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1), slots: 8, levels: 3, capacity: 100
        )
        #expect(config.levelRange(config.levels - 1) == config.rangeTicks)
    }

    @Test
    func `different slot sizes produce correct derived constants`() {
        for shift in 1...8 {
            let slots = 1 << shift
            let config = Async.Timer.Wheel<ContinuousClock>.Config(
                tick: .milliseconds(1), slots: slots, levels: 2, capacity: 100
            )
            #expect(config.slotShift == shift)
            #expect(config.slotMask == slots - 1)
            #expect(config.rangeTicks == UInt64(slots) * UInt64(slots))
        }
    }
}
