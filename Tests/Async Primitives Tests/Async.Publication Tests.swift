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

/// Test namespace for Async.Publication (generic type requires wrapper for #Tests).
enum Publication {
    enum Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Publication.Test.Unit {
    @Test
    func `init creates empty slot`() {
        let publication = Async.Publication<Int>()
        let taken = publication.take()
        #expect(taken == nil)
    }

    @Test
    func `init with value creates non-empty slot`() {
        let publication = Async.Publication<Int>(42)
        let taken = publication.take()
        #expect(taken == 42)
    }

    @Test
    func `publish sets value`() {
        let publication = Async.Publication<Int>()
        publication.publish(42)
        let taken = publication.take()
        #expect(taken == 42)
    }

    @Test
    func `take clears slot`() {
        let publication = Async.Publication<Int>()
        publication.publish(42)
        _ = publication.take()
        let secondTake = publication.take()
        #expect(secondTake == nil)
    }

    @Test
    func `latest publish dominates earlier values`() {
        let publication = Async.Publication<Int>()
        publication.publish(1)
        publication.publish(2)
        publication.publish(3)

        let taken = publication.take()
        #expect(taken == 3)
    }

    @Test
    func `multiple takes after single publish - single winner`() {
        let publication = Async.Publication<Int>()
        publication.publish(42)

        let first = publication.take()
        let second = publication.take()
        let third = publication.take()

        #expect(first == 42)
        #expect(second == nil)
        #expect(third == nil)
    }
}

// MARK: - Edge Cases

extension Publication.Test.EdgeCase {
    @Test
    func `take on never-published slot`() {
        let publication = Async.Publication<String>()
        #expect(publication.take() == nil)
        #expect(publication.take() == nil)
    }

    @Test
    func `publish after take resets slot`() {
        let publication = Async.Publication<Int>()
        publication.publish(1)
        _ = publication.take()
        publication.publish(2)
        #expect(publication.take() == 2)
    }

    @Test
    func `rapid publish-take cycles`() {
        let publication = Async.Publication<Int>()

        for i in 0..<1000 {
            publication.publish(i)
            let taken = publication.take()
            #expect(taken == i)
        }
    }
}

// MARK: - Concurrency / Stress Tests

extension Publication.Test.Performance {

    // MARK: - Single-Winner Linearization

    @Test
    func `concurrent take race - exactly one winner`() async {
        // Multiple tasks racing to take the same value.
        // Exactly one should win, others get nil.
        // This tests single-winner linearization.
        for round in 0..<100 {
            let publication = Async.Publication<Int>()
            let publishedValue = round * 1000 + 42
            publication.publish(publishedValue)

            let results = await withTaskGroup(of: Int?.self) { group in
                for _ in 0..<10 {
                    group.addTask {
                        publication.take()
                    }
                }

                var results: [Int?] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            // Exactly one winner
            let winners = results.compactMap { $0 }
            #expect(winners.count == 1, "Expected exactly 1 winner, got \(winners.count) in round \(round)")

            // Winner got the correct value
            #expect(winners.first == publishedValue)

            // Losers get nil
            let losers = results.filter { $0 == nil }
            #expect(losers.count == 9)
        }
    }

    // MARK: - Visibility / Happens-Before

    @Test
    func `publish happens-before take visibility`() async {
        // This test verifies that publish() synchronizes with take().
        // If publication relied on unsynchronized memory, take() could
        // observe stale or garbage values.
        let publication = Async.Publication<Int>()
        let iterations = 1_000
        let range = 0..<iterations

        await withTaskGroup(of: Void.self) { group in
            // Publisher: publish values in known range
            group.addTask {
                for i in range {
                    publication.publish(i)
                    await Task.yield()
                }
            }

            // Taker: try to observe at least one value
            group.addTask {
                var seen = false
                for _ in 0..<(iterations * 10) {
                    if let value = publication.take() {
                        // Value must be in the published range (no garbage)
                        #expect(range.contains(value), "Observed out-of-range value: \(value)")
                        seen = true
                        break
                    }
                    await Task.yield()
                }
                // Must eventually observe something (visibility guarantee)
                #expect(seen, "Never observed any published value - visibility failure")
            }
        }
    }

    // MARK: - Interleaving with Assertions

    @Test
    func `publish-take interleaving observes valid values`() async {
        // Concurrent publish and take with assertions on observed values.
        // This is stronger than "no crash" - it asserts semantic correctness.
        let publication = Async.Publication<Int>()
        let iterations = 1_000
        let range = 0..<iterations

        let ends = Async.Channel<Int>.Unbounded().take().ends()

        await withTaskGroup(of: Void.self) { group in
            // Publisher
            group.addTask {
                for i in range {
                    publication.publish(i)
                    await Task.yield()
                }
            }

            // Taker
            group.addTask { [sender = ends.sender] in
                for _ in range {
                    if let value = publication.take() {
                        try? sender.send(value)
                    }
                    await Task.yield()
                }
            }
        }

        ends.close()

        // Collect observed values
        var observed: [Int] = []
        while let value = try? await ends.receiver.receive() {
            observed.append(value)
        }

        // Must have observed at least some values
        #expect(!observed.isEmpty, "No values observed during interleaving")

        // All observed values must be in the published range (no garbage)
        for value in observed {
            #expect(range.contains(value), "Observed out-of-range value: \(value)")
        }
    }

    // MARK: - High Contention Admissibility

    @Test
    func `high contention publish-take admissibility`() async {
        // Multiple publishers and takers racing.
        // Assert: all observed values are in the published range.
        let publication = Async.Publication<Int>()
        let publisherCount = 5
        let takerCount = 5
        let iterationsPerActor = 100
        let totalRange = 0..<(publisherCount * iterationsPerActor)

        let ends = Async.Channel<Int>.Unbounded().take().ends()

        await withTaskGroup(of: Void.self) { group in
            // Multiple publishers
            for p in 0..<publisherCount {
                group.addTask {
                    let base = p * iterationsPerActor
                    for j in 0..<iterationsPerActor {
                        publication.publish(base + j)
                        await Task.yield()
                    }
                }
            }

            // Multiple takers
            for _ in 0..<takerCount {
                group.addTask { [sender = ends.sender] in
                    for _ in 0..<iterationsPerActor {
                        if let value = publication.take() {
                            try? sender.send(value)
                        }
                        await Task.yield()
                    }
                }
            }
        }

        ends.close()

        // Collect and validate
        var observed: [Int] = []
        while let value = try? await ends.receiver.receive() {
            observed.append(value)
        }

        // All observed values must be in the admissible range
        for value in observed {
            #expect(totalRange.contains(value), "Observed inadmissible value: \(value)")
        }

        // Should have observed at least some values
        #expect(!observed.isEmpty, "No values observed under high contention")
    }

    // MARK: - Cancellation Bridge Pattern

    @Test
    func `cancellation bridge pattern - token race`() async {
        // This tests the actual pattern Publication is designed for:
        // publish a token, then race between operation completion and cancellation.
        // Exactly one path should claim the token.

        for round in 0..<100 {
            let publication = Async.Publication<Int>()
            let token = round + 1

            // Simulate the pattern used in Unbounded.receive() and Broadcast.next()
            let result = await withTaskGroup(of: String.self) { group in
                // "Operation" path: publishes token, then tries to claim it
                group.addTask {
                    publication.publish(token)

                    // Yield to allow interleaving
                    await Task.yield()

                    // Try to claim (simulates early-cancellation window check)
                    if let taken = publication.take() {
                        return "operation:\(taken)"
                    }
                    return "operation:lost"
                }

                // "Cancellation" path: tries to claim the token
                group.addTask {
                    // Yield to allow interleaving
                    await Task.yield()

                    if let taken = publication.take() {
                        return "cancel:\(taken)"
                    }
                    return "cancel:lost"
                }

                var outcomes: [String] = []
                for await outcome in group {
                    outcomes.append(outcome)
                }
                return outcomes
            }

            // Exactly one path should have claimed the token
            let claimers = result.filter { !$0.hasSuffix(":lost") }
            #expect(claimers.count == 1, "Expected exactly 1 claimer, got \(claimers.count) in round \(round): \(result)")

            // The claimed token must be correct
            if let winner = claimers.first {
                #expect(winner.hasSuffix(":\(token)"), "Winner claimed wrong token: \(winner)")
            }
        }
    }
}
