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

// Broadcast channel performance: send throughput, iteration throughput,
// concurrent round-trips. Exercises forEach iteration (P-1), Publication
// reuse (P-2), and allocation-free fast paths (P-3).

import Async_Primitives
import Testing

// MARK: - Broadcast

extension Benchmark {
    @Suite struct Broadcast {}
}

// MARK: - Send Throughput

extension Benchmark.Broadcast {

    /// Send throughput with many subscribers.
    ///
    /// Exercises the forEach-based subscriber iteration path.
    /// Pre-optimization: O(total_subscribers) key snapshot allocation per send.
    /// Post-optimization: O(waking_subscribers) allocation per send.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 sends to 50 subscribers`() async throws {
        let broadcast = Async.Broadcast<Int>(bufferCapacity: Benchmark.iterations)
        let subscriptions = (0..<50).map { _ in broadcast.subscribe() }

        for i in 0..<Benchmark.iterations {
            broadcast.send(i)
        }
        broadcast.finish()

        for sub in subscriptions {
            var count = 0
            for try await _ in sub { count += 1 }
            #expect(count == Benchmark.iterations)
        }
    }

    /// Send throughput with few subscribers (common case).
    ///
    /// Baseline: forEach overhead is negligible with small subscriber counts.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 sends to 3 subscribers`() async throws {
        let broadcast = Async.Broadcast<Int>(bufferCapacity: Benchmark.iterations)
        let subscriptions = (0..<3).map { _ in broadcast.subscribe() }

        for i in 0..<Benchmark.iterations {
            broadcast.send(i)
        }
        broadcast.finish()

        for sub in subscriptions {
            var count = 0
            for try await _ in sub { count += 1 }
            #expect(count == Benchmark.iterations)
        }
    }
}

// MARK: - Iteration Throughput

extension Benchmark.Broadcast {

    /// Iteration throughput from pre-buffered elements.
    ///
    /// Exercises Publication reuse across next() calls.
    /// Pre-optimization: one Publication class allocation per next().
    /// Post-optimization: one Publication per makeAsyncIterator(), reused.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 buffered iterations`() async throws {
        let broadcast = Async.Broadcast<Int>(bufferCapacity: Benchmark.iterations)
        let subscription = broadcast.subscribe()

        for i in 0..<Benchmark.iterations {
            broadcast.send(i)
        }
        broadcast.finish()

        var count = 0
        for try await _ in subscription { count += 1 }
        #expect(count == Benchmark.iterations)
    }
}

// MARK: - Concurrent Round-Trips

extension Benchmark.Broadcast {

    /// Concurrent producer/consumer round-trips.
    ///
    /// Combines send throughput (forEach) and iteration (Publication reuse)
    /// under concurrent scheduling pressure.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 round-trips with 10 subscribers`() async throws {
        let broadcast = Async.Broadcast<Int>(bufferCapacity: Benchmark.iterations)
        let subscriptions = (0..<10).map { _ in broadcast.subscribe() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<Benchmark.iterations {
                    broadcast.send(i)
                }
                broadcast.finish()
            }

            for sub in subscriptions {
                group.addTask {
                    var count = 0
                    for try await _ in sub { count += 1 }
                    #expect(count == Benchmark.iterations)
                }
            }

            try await group.waitForAll()
        }
    }
}
