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

import Async_Primitives
import Testing

@Suite("Async.Channel.Unbounded")
struct UnboundedChannelTests {

    @Test("Send and receive single element")
    func sendReceiveSingleElement() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(42)
        ends.close()
        let value = try await ends.receiver.receive()
        #expect(value == 42)
    }

    @Test("Send succeeds when channel is open")
    func sendSucceedsWhenOpen() throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        try ends.sender.send(42)
        ends.close()
    }

    @Test("Closed channel rejects send")
    func closedChannelRejectsSend() {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        ends.close()
        #expect(throws: Async.Channel<Int>.Error.closed) {
            try ends.sender.send(42)
        }
    }

    @Test("Receive returns nil after close and drain")
    func receiveReturnsNilAfterCloseAndDrain() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(1)
        try ends.sender.send(2)
        ends.close()

        let first = try await ends.receiver.receive()
        let second = try await ends.receiver.receive()
        let third = try await ends.receiver.receive()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == nil)
    }

    @Test("Poll returns nil when empty")
    func pollReturnsNilWhenEmpty() {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let result = ends.receiver.poll()
        #expect(result == nil)
    }

    @Test("Poll returns element when available")
    func pollReturnsElement() throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(42)
        let result = ends.receiver.poll()
        #expect(result == 42)
    }

    @Test("Send batch elements")
    func sendBatch() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(contentsOf: [1, 2, 3])
        ends.close()

        var received: [Int] = []
        while let value = try await ends.receiver.receive() {
            received.append(value)
        }
        #expect(received == [1, 2, 3])
    }

    @Test("closed reflects state")
    func closedReflectsState() {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        #expect(ends.sender.closed == false)
        #expect(ends.receiver.closed == false)
        ends.close()
        #expect(ends.sender.closed == true)
        #expect(ends.receiver.closed == true)
    }

    @Test("Receive suspends until element available")
    func receiveSuspendsUntilElement() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        // Use elements for Task (Elements is Sendable)
        let elements = ends.receiver.elements
        let sender = ends.sender

        // Start receive in background
        let receiveTask = Task {
            await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for task to be ready
        await started.arrive()

        // Send element
        try sender.send(42)

        // Receive should complete with the element
        let result = try await receiveTask.value
        #expect(result == 42)
    }

    @Test("Receive resumes with nil on close")
    func receiveResumesOnClose() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        // Start receive in background
        let receiveTask = Task {
            await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for task to be ready
        await started.arrive()

        // Close channel
        sender.close()

        // Receive should complete with nil
        let result = try await receiveTask.value
        #expect(result == nil)
    }

    @Test("Multiple producers can send concurrently")
    func multipleProducers() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender = ends.sender
        let count = 100

        // Launch multiple producer tasks
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    try sender.send(i)
                }
            }
        }

        sender.close()

        // Collect all received values
        var received: Set<Int> = []
        while let value = try await ends.receiver.receive() {
            received.insert(value)
        }

        // Should have received all values
        #expect(received.count == count)
        for i in 0..<count {
            #expect(received.contains(i))
        }
    }

    @Test("Cancellation throws cancelled error")
    func cancellationThrowsCancelled() async {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements

        let receiveTask = Task {
            await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for task to be ready
        await started.arrive()

        // Cancel the task
        receiveTask.cancel()

        // Should throw cancelled error
        do {
            _ = try await receiveTask.value
            Issue.record("Expected cancellation error")
        } catch let error as Async.Channel<Int>.Error {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Close with buffered elements drains then returns nil")
    func closeWithBufferedElementsDrainsThenNil() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        // Buffer elements
        try ends.sender.send(1)
        try ends.sender.send(2)
        try ends.sender.send(3)

        // Close while buffer is non-empty
        ends.close()

        // Should be able to drain all buffered elements
        let first = try await ends.receiver.receive()
        let second = try await ends.receiver.receive()
        let third = try await ends.receiver.receive()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)

        // After drain, should return nil
        let fourth = try await ends.receiver.receive()
        #expect(fourth == nil)
    }

    @Test("Sender copies share storage")
    func senderCopiesShareStorage() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender1 = ends.sender
        let sender2 = sender1  // Copy

        // Send from both senders
        try sender1.send(1)
        try sender2.send(2)

        // Both should go to same channel (FIFO order)
        let first = ends.receiver.poll()
        let second = ends.receiver.poll()

        #expect(first == 1)
        #expect(second == 2)

        // Close from one sender closes for both
        sender1.close()
        #expect(sender2.closed == true)
        #expect(ends.receiver.closed == true)
    }

    @Test("Direct delivery when receiver waiting")
    func directDeliveryWhenReceiverWaiting() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        // Start receiver first (will suspend)
        let receiveTask = Task {
            await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for receiver to be ready
        await started.arrive()

        // Send element - should be delivered directly
        try sender.send(42)

        // Receiver should get the element
        let value = try await receiveTask.value
        #expect(value == 42)

        // Buffer should be empty (element was delivered directly)
        let remaining = ends.receiver.poll()
        #expect(remaining == nil)
    }

    @Test("AsyncSequence iteration")
    func asyncSequenceIteration() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(contentsOf: [1, 2, 3])
        ends.close()

        var received: [Int] = []
        for try await value in ends.receiver.elements {
            received.append(value)
        }

        #expect(received == [1, 2, 3])
    }

    @Test("Poll does not affect suspension state")
    func pollDoesNotAffectSuspension() async throws {
        var ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)
        let sender = ends.sender

        // Poll returns nil when empty (before any suspension)
        #expect(ends.receiver.poll() == nil)

        // Use elements for the background task
        let elements = ends.receiver.elements

        // Start a suspended receive
        let receiveTask = Task {
            await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        await started.arrive()

        // NOTE: We intentionally do NOT poll while receiveTask is suspended
        // because that would violate single-suspended-receiver invariant

        // Send an element
        try sender.send(42)

        // Receive should get it
        let value = try await receiveTask.value
        #expect(value == 42)
    }
}
