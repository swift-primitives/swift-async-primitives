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

// Bounded channel performance: round-trip latency, backpressure.
// Post-optimization baseline (flat state, no CoW traps).

import Async_Primitives
import Testing

// MARK: - Bounded Channel

extension Benchmark {
    @Suite struct BoundedChannel {}
}

// MARK: - Round-Trips

extension Benchmark.BoundedChannel {

    /// Bounded channel round-trip with capacity=1 (full backpressure).
    ///
    /// This is the most demanding mode: every send suspends until the
    /// receiver consumes. Measures state machine + suspension overhead.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 round-trips capacity 1`() async throws {
        let channel = Async.Channel<Int>.Bounded(capacity: 1)
        let sender = channel.sender

        let producer = Task.detached {
            for i in 0..<Benchmark.iterations {
                try await sender.send(i)
            }
        }

        for _ in 0..<Benchmark.iterations {
            _ = try await channel.receiver.receive()
        }

        _ = try await producer.value
    }

    /// Bounded channel with large capacity (send never suspends).
    ///
    /// Isolates state machine overhead from suspension cost.
    /// All sends hit the fast path (buffer has space).
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 round-trips capacity 1000`() async throws {
        let channel = Async.Channel<Int>.Bounded(capacity: Benchmark.iterations)
        let sender = channel.sender

        let producer = Task.detached {
            for i in 0..<Benchmark.iterations {
                try await sender.send(i)
            }
        }

        for _ in 0..<Benchmark.iterations {
            _ = try await channel.receiver.receive()
        }

        _ = try await producer.value
    }

    /// Synchronous send via send.immediate (no async overhead).
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 immediate sends capacity 1000`() async throws {
        let channel = Async.Channel<Int>.Bounded(capacity: Benchmark.iterations)
        let sender = channel.sender

        let producer = Task.detached {
            for i in 0..<Benchmark.iterations {
                try sender.send.immediate(i)
            }
        }

        for _ in 0..<Benchmark.iterations {
            _ = try await channel.receiver.receive()
        }

        _ = try await producer.value
    }
}
