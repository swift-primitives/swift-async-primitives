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

// Unbounded channel performance: batch send vs per-element send,
// concurrent round-trips. Exercises single-lock batch optimization (P-4).

import Async_Primitives
import Testing

// MARK: - Unbounded Channel

extension Benchmark {
    @Suite struct UnboundedChannel {}
}

// MARK: - Batch Send

extension Benchmark.UnboundedChannel {

    /// Batch send throughput (single lock acquisition).
    ///
    /// Post-optimization: send(contentsOf:) holds lock once for all elements.
    /// First element delivered to waiting receiver, rest buffered.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 batch send`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let elements = Array(0..<Benchmark.iterations)

        try ends.sender.send(contentsOf: elements)
        ends.close()

        var count = 0
        while let _ = try await ends.receiver.receive() { count += 1 }
        #expect(count == Benchmark.iterations)
    }

    /// Per-element send throughput (one lock per element).
    ///
    /// Baseline for comparison with batch send.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 per-element send`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        for i in 0..<Benchmark.iterations {
            try ends.sender.send(i)
        }
        ends.close()

        var count = 0
        while let _ = try await ends.receiver.receive() { count += 1 }
        #expect(count == Benchmark.iterations)
    }
}

// MARK: - Round-Trips

extension Benchmark.UnboundedChannel {

    /// Concurrent producer/consumer round-trips (single element).
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 round-trips`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        let producer = Task.detached {
            for i in 0..<Benchmark.iterations {
                try ends.sender.send(i)
            }
        }

        for _ in 0..<Benchmark.iterations {
            _ = try await ends.receiver.receive()
        }

        _ = try await producer.value
        ends.close()
    }

    /// Concurrent batch send with receiver.
    @Test(.timed(iterations: 10, warmup: 2))
    func `1000 batch round-trips`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let receiver = Task {
            await started.arrive()
            var count = 0
            while let _ = try await ends.receiver.receive() { count += 1 }
            return count
        }

        await started.arrive()
        let elements = Array(0..<Benchmark.iterations)
        try ends.sender.send(contentsOf: elements)
        ends.close()

        let count = try await receiver.value
        #expect(count == Benchmark.iterations)
    }
}
