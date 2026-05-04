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
    func `slot mask is slots minus one`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 16,
            levels: 2,
            capacity: 100
        )
        #expect(config.slot.mask == 15)
    }

    @Test
    func `slot shift is log2 of slots`() {
        let config8 = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 2,
            capacity: 100
        )
        #expect(config8.slot.shift == 3)

        let config64 = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 64,
            levels: 2,
            capacity: 100
        )
        #expect(config64.slot.shift == 6)
    }

    @Test
    func `range ticks is slots to the power of levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        // 8^3 = 512; computed as 1 << (3 * 3) = 1 << 9 = 512
        #expect(config.range.ticks == 512)
    }

    @Test
    func `level range returns cumulative range per level`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        // Level 0: 1 << (1*3) = 8
        #expect(config.level.range(0) == 8)
        // Level 1: 1 << (2*3) = 64
        #expect(config.level.range(1) == 64)
        // Level 2: 1 << (3*3) = 512
        #expect(config.level.range(2) == 512)
    }

    @Test
    func `ticks per slot returns ticks per slot at each level`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        // Level 0: 1 tick per slot
        #expect(config.ticks.perSlot(0) == 1)
        // Level 1: 8 ticks per slot
        #expect(config.ticks.perSlot(1) == 8)
        // Level 2: 64 ticks per slot
        #expect(config.ticks.perSlot(2) == 64)
    }

    @Test
    func `duration computes maximum schedulable duration`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(10),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        // 512 ticks × 10ms per tick = 5.12 seconds
        let duration = config.duration
        #expect(duration >= .seconds(5))
        #expect(duration <= .seconds(6))
    }

    @Test
    func `default config range ticks is 64 to the 6th`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config.default
        // 64^6 = 2^36 = 68,719,476,736
        #expect(config.range.ticks == 68_719_476_736)
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
            tick: .milliseconds(5),
            slots: 16,
            levels: 4,
            capacity: 256
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
            tick: .milliseconds(1),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        let b = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        let c = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(2),
            slots: 8,
            levels: 3,
            capacity: 100
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
            tick: .nanoseconds(1),
            slots: 2,
            levels: 1,
            capacity: 1
        )
        #expect(config.slot.mask == 1)
        #expect(config.slot.shift == 1)
        #expect(config.range.ticks == 2)
        #expect(config.level.range(0) == 2)
        #expect(config.ticks.perSlot(0) == 1)
    }

    @Test
    func `config with maximum levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 4,
            levels: 8,
            capacity: 100
        )
        // 4^8 = 2^16 = 65536
        #expect(config.range.ticks == 65536)
    }

    @Test
    func `config with large slot count`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 256,
            levels: 2,
            capacity: 100
        )
        #expect(config.slot.mask == 255)
        #expect(config.slot.shift == 8)
        // 256^2 = 65536
        #expect(config.range.ticks == 65536)
    }

    @Test
    func `ticks per slot increases geometrically across levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 4,
            capacity: 100
        )
        for level in 1..<config.levels {
            #expect(
                config.ticks.perSlot(level) == config.ticks.perSlot(level - 1) * UInt64(config.slots)
            )
        }
    }

    @Test
    func `level range increases geometrically across levels`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 16,
            levels: 4,
            capacity: 100
        )
        for level in 1..<config.levels {
            #expect(
                config.level.range(level) == config.level.range(level - 1) * UInt64(config.slots)
            )
        }
    }

    @Test
    func `highest level range equals range ticks`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 8,
            levels: 3,
            capacity: 100
        )
        #expect(config.level.range(config.levels - 1) == config.range.ticks)
    }

    @Test
    func `different slot sizes produce correct derived constants`() {
        for shift in 1...8 {
            let slots = 1 << shift
            let config = Async.Timer.Wheel<ContinuousClock>.Config(
                tick: .milliseconds(1),
                slots: slots,
                levels: 2,
                capacity: 100
            )
            #expect(config.slot.shift == shift)
            #expect(config.slot.mask == slots - 1)
            #expect(config.range.ticks == UInt64(slots) * UInt64(slots))
        }
    }
}

// MARK: - Release-mode regression guard (Finding #12 narrow-shape watchflag)
//
// Parity regression guard for the V11 narrow-shape compiler bug
// documented at swift-institute/Audits/borrow-pointer-storage-release-
// miscompile.md finding #12, archived at the experiment
// swift-institute/Experiments/borrow-pointer-storage-release-miscompile
// V10/V11 (commit cee7a7a).
//
// Scope caveat: Async.Timer.Wheel's internal storage goes through
// Buffer<Node>.Arena.Bounded, which uses heap-allocated raw memory
// (stable pointer by construction) — NOT Memory.Inline's `@_rawLayout`
// field-of-self shape. The V11 failure mode is structurally impossible
// on this code path. This test exists for 3/3 parity across the audit's
// enumerated cascade (swift-memory-primitives + swift-buffer-primitives
// + swift-async-primitives) and asserts Wheel public state remains
// consistent across repeated cross-module reads on a `let`-bound
// instance. Any release-mode optimizer regression that widened the
// bug class to cascade through Buffer.Arena's heap-backed path would
// surface here.

extension Timer.Wheel.Test.Unit {
    @Test
    func `wheel state remains consistent across repeated cross-module reads (finding #12 regression guard)`() {
        let config = Async.Timer.Wheel<ContinuousClock>.Config(
            tick: .milliseconds(1),
            slots: 16,
            levels: 2,
            capacity: 64
        )
        let wheel = Async.Timer.Wheel(clock: ContinuousClock(), config: config)

        let count1 = wheel.count
        let count2 = wheel.count
        let isEmpty1 = wheel.isEmpty
        let isEmpty2 = wheel.isEmpty
        let cfg1 = wheel.config
        let cfg2 = wheel.config

        #expect(count1 == count2)
        #expect(count1 == 0)
        #expect(isEmpty1 == isEmpty2)
        #expect(isEmpty1 == true)
        #expect(cfg1 == cfg2)
        #expect(cfg1 == config)
    }
}
