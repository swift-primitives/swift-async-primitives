// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025-2026 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Async_Primitives_Test_Support
import Synchronization
import Testing

// MARK: - Test Suites

extension Async.Semaphore {
    enum Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Integration {}
    }
}

// MARK: - Shared Test Infrastructure

/// Sendable counter for cross-task coordination.
private final class Counter: Sendable {
    private let _value: Mutex<Int>
    private let _peak: Mutex<Int>

    init(_ initial: Int = 0) {
        self._value = Mutex(initial)
        self._peak = Mutex(initial)
    }

    var value: Int { _value.withLock { $0 } }
    var peak: Int { _peak.withLock { $0 } }

    func increment() {
        let current = _value.withLock { val -> Int in
            val += 1
            return val
        }
        _peak.withLock { p in
            if current > p { p = current }
        }
    }

    func decrement() {
        _value.withLock { $0 -= 1 }
    }
}

/// Sendable array collector.
private final class Collector<T: Sendable>: Sendable {
    private let _values: Mutex<[T]>

    init() { self._values = Mutex([]) }

    func append(_ value: T) {
        _values.withLock { $0.append(value) }
    }

    var values: [T] { _values.withLock { $0 } }
    var count: Int { _values.withLock { $0.count } }
}

// MARK: - Unit Tests

extension Async.Semaphore.Test.Unit {
    @Test
    func `init creates semaphore with correct capacity`() {
        let semaphore = Async.Semaphore(capacity: 3)
        let metrics = semaphore.metrics
        #expect(metrics.currentOutstanding == 0)
        #expect(metrics.currentWaiters == 0)
        #expect(metrics.acquisitions == 0)
    }

    @Test
    func `wait acquires permit immediately when available`() async throws {
        let semaphore = Async.Semaphore(capacity: 2)
        try await semaphore.wait()
        let metrics = semaphore.metrics
        #expect(metrics.acquisitions == 1)
        #expect(metrics.currentOutstanding == 1)
    }

    @Test
    func `signal releases permit`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)
        try await semaphore.wait()
        semaphore.signal()
        let metrics = semaphore.metrics
        #expect(metrics.acquisitions == 1)
        #expect(metrics.releases == 1)
        #expect(metrics.currentOutstanding == 0)
    }

    @Test
    func `multiple acquires up to capacity succeed immediately`() async throws {
        let semaphore = Async.Semaphore(capacity: 3)
        try await semaphore.wait()
        try await semaphore.wait()
        try await semaphore.wait()
        let metrics = semaphore.metrics
        #expect(metrics.acquisitions == 3)
        #expect(metrics.currentOutstanding == 3)
    }

    @Test
    func `signal resumes suspended waiter`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)
        try await semaphore.wait()

        let resumed = Counter()
        let task = Task {
            try await semaphore.wait()
            resumed.increment()
        }

        // Give the task time to suspend
        try? await Task.sleep(for: .milliseconds(50))

        // Signal should resume the waiting task
        semaphore.signal()
        try await task.value

        #expect(resumed.value == 1)
        #expect(semaphore.metrics.acquisitions == 2)
    }

    @Test
    func `withPermit acquires and releases`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)

        try await semaphore.withPermit {
            #expect(semaphore.metrics.currentOutstanding == 1)
        }

        #expect(semaphore.metrics.currentOutstanding == 0)
        #expect(semaphore.metrics.acquisitions == 1)
        #expect(semaphore.metrics.releases == 1)
    }

    @Test
    func `metrics track peak outstanding`() async throws {
        let semaphore = Async.Semaphore(capacity: 5)

        try await semaphore.wait()
        try await semaphore.wait()
        try await semaphore.wait()

        #expect(semaphore.metrics.peakOutstanding == 3)

        semaphore.signal()
        semaphore.signal()

        #expect(semaphore.metrics.peakOutstanding == 3)
        #expect(semaphore.metrics.currentOutstanding == 1)
    }
}

// MARK: - Edge Case Tests

extension Async.Semaphore.Test.`Edge Case` {
    @Test
    func `shutdown wakes all waiters`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)
        try await semaphore.wait()

        let shutdownCount = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    do {
                        try await semaphore.wait()
                    } catch {
                        shutdownCount.increment()
                    }
                }
            }

            // Give tasks time to suspend
            try? await Task.sleep(for: .milliseconds(50))

            semaphore.shutdown()
        }

        #expect(shutdownCount.value == 3)
    }

    @Test
    func `wait after shutdown throws immediately`() async {
        let semaphore = Async.Semaphore(capacity: 1)
        semaphore.shutdown()

        do {
            try await semaphore.wait()
            Issue.record("Expected shutdown error")
        } catch {
            #expect(error == .shutdown)
        }
    }

    @Test
    func `shutdown is idempotent`() {
        let semaphore = Async.Semaphore(capacity: 1)
        semaphore.shutdown()
        semaphore.shutdown()  // Should not crash
        #expect(semaphore.isShutdown)
    }

    @Test
    func `cancellation wakes waiter with error`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)
        try await semaphore.wait()

        let task = Task {
            try await semaphore.wait()
        }

        // Give task time to suspend
        try? await Task.sleep(for: .milliseconds(50))

        task.cancel()

        do {
            try await task.value
            Issue.record("Expected cancellation error")
        } catch {
            // Expected: cancelled
        }
    }

    @Test
    func `timeout fires correctly`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)
        try await semaphore.wait()

        do {
            try await semaphore.wait(timeout: .milliseconds(50))
            Issue.record("Expected timeout error")
        } catch {
            #expect(error == .timeout)
        }

        #expect(semaphore.metrics.timeouts == 1)
    }
}

// MARK: - Integration Tests

extension Async.Semaphore.Test.Integration {
    @Test
    func `FIFO ordering under contention`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)
        try await semaphore.wait()

        let order = Collector<Int>()

        await withTaskGroup(of: Void.self) { group in
            // Launch tasks with stagger to ensure FIFO ordering
            for i in 0..<3 {
                group.addTask {
                    do {
                        try await semaphore.wait()
                        order.append(i)
                        semaphore.signal()
                    } catch {
                        // Shutdown/cancellation — skip
                    }
                }
                // Stagger to ensure FIFO order
                try? await Task.sleep(for: .milliseconds(20))
            }

            // Release the initial permit to start the chain
            semaphore.signal()
        }

        #expect(order.values == [0, 1, 2])
    }

    @Test
    func `concurrent stress test enforces capacity limit`() async throws {
        let capacity = 3
        let taskCount = 10
        let semaphore = Async.Semaphore(capacity: capacity)

        let concurrent = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    do {
                        try await semaphore.wait()

                        concurrent.increment()

                        // Simulate work
                        try? await Task.sleep(for: .milliseconds(10))

                        concurrent.decrement()
                        semaphore.signal()
                    } catch {
                        Issue.record("Unexpected error: \(error)")
                    }
                }
            }
        }

        #expect(concurrent.peak <= capacity)
        #expect(semaphore.metrics.acquisitions == UInt64(taskCount))
        #expect(semaphore.metrics.releases == UInt64(taskCount))
    }

    @Test
    func `withPermit holds permit for body duration`() async throws {
        let semaphore = Async.Semaphore(capacity: 1)

        let task = Task {
            try await semaphore.withPermit {
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        // Give time for the withPermit to acquire
        try? await Task.sleep(for: .milliseconds(20))

        // Trying to acquire should block because capacity is 1
        #expect(semaphore.metrics.currentOutstanding == 1)

        try await task.value

        // Permit should be released after body completes
        #expect(semaphore.metrics.currentOutstanding == 0)
    }

    @Test
    func `metrics accuracy after mixed operations`() async throws {
        let semaphore = Async.Semaphore(capacity: 2)

        // Acquire 2 permits
        try await semaphore.wait()
        try await semaphore.wait()

        // Start a task that will be cancelled
        let cancelTask = Task {
            try await semaphore.wait()
        }
        try? await Task.sleep(for: .milliseconds(30))
        cancelTask.cancel()
        do { try await cancelTask.value } catch {}

        // Signal both permits back
        semaphore.signal()
        semaphore.signal()

        let metrics = semaphore.metrics
        #expect(metrics.acquisitions == 2)
        #expect(metrics.releases == 2)
        #expect(metrics.currentOutstanding == 0)
        #expect(metrics.cancellations == 1)
    }
}
