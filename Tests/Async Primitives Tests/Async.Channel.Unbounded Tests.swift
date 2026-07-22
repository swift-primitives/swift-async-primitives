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

@Suite
struct UnboundedChannelTests {

    @Test
    func `Send and receive single element`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(42)
        ends.close()
        let value = try await ends.receiver.receive()
        #expect(value == 42)
    }

    @Test
    func `Send succeeds when channel is open`() throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        try ends.sender.send(42)
        ends.close()
    }

    @Test
    func `Closed channel rejects send`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        ends.close()
        #expect(throws: Async.Channel<Int>.Error.closed) {
            try ends.sender.send(42)
        }
    }

    @Test
    func `Receive returns nil after close and drain`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

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

    @Test
    func `Poll returns nil when empty`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let result = ends.receiver.poll()
        #expect(result == nil)
    }

    @Test
    func `Poll returns element when available`() throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(42)
        let result = ends.receiver.poll()
        #expect(result == 42)
    }

    @Test
    func `Send batch elements`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(contentsOf: [1, 2, 3])
        ends.close()

        var received: [Int] = []
        while let value = try await ends.receiver.receive() {
            received.append(value)
        }
        #expect(received == [1, 2, 3])
    }

    @Test
    func `closed reflects state`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        #expect(ends.sender.closed == false)
        #expect(ends.receiver.closed == false)
        ends.close()
        #expect(ends.sender.closed == true)
        #expect(ends.receiver.closed == true)
    }

    @Test
    func `Receive suspends until element available`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        // Use elements for Task (Elements is Sendable)
        let elements = ends.receiver.elements
        let sender = ends.sender

        // Start receive in background
        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for task to be ready
        try? await started.arrive()

        // Send element
        try sender.send(42)

        // Receive should complete with the element
        let result = try await receiveTask.value
        #expect(result == 42)
    }

    @Test
    func `Receive resumes with nil on close`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        // Start receive in background
        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for task to be ready
        try? await started.arrive()

        // Close channel
        sender.close()

        // Receive should complete with nil
        let result = try await receiveTask.value
        #expect(result == nil)
    }

    @Test
    func `Multiple producers can send concurrently`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
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

    @Test
    func `Cancellation throws cancelled error`() async {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements

        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for task to be ready
        try? await started.arrive()

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

    @Test
    func `Close with buffered elements drains then returns nil`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

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

    @Test
    func `Sender copies share storage`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
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

    @Test
    func `Sender copies compare equal by endpoint identity`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender = ends.sender
        let copy = sender

        #expect(sender == copy)
    }

    @Test
    func `Senders from distinct channels compare unequal`() {
        let first = Async.Channel<Int>.Unbounded().take().ends()
        let second = Async.Channel<Int>.Unbounded().take().ends()

        #expect(first.sender != second.sender)
    }

    @Test
    func `Sender equality remains stable after close`() {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let sender = ends.sender
        let copy = sender

        sender.close()

        #expect(sender == copy)
    }

    @Test
    func `Sender equality supports noncopyable elements`() {
        final class Payload {}
        struct Parcel: ~Copyable {
            let payload: Payload
        }

        let ends = Async.Channel<Parcel>.Unbounded().take().ends()
        let sender = ends.sender
        let copy = sender

        #expect(sender == copy)
    }

    @Test
    func `Direct delivery when receiver waiting`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)

        let elements = ends.receiver.elements
        let sender = ends.sender

        // Start receiver first (will suspend)
        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        // Wait for receiver to be ready
        try? await started.arrive()

        // Send element - should be delivered directly
        try sender.send(42)

        // Receiver should get the element
        let value = try await receiveTask.value
        #expect(value == 42)

        // Buffer should be empty (element was delivered directly)
        let remaining = ends.receiver.poll()
        #expect(remaining == nil)
    }

    @Test
    func `AsyncSequence iteration`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()

        try ends.sender.send(contentsOf: [1, 2, 3])
        ends.close()

        var received: [Int] = []
        for try await value in ends.receiver.elements {
            received.append(value)
        }

        #expect(received == [1, 2, 3])
    }

    @Test
    func `Poll does not affect suspension state`() async throws {
        let ends = Async.Channel<Int>.Unbounded().take().ends()
        let started = Async.Barrier(parties: 2)
        let sender = ends.sender

        // Poll returns nil when empty (before any suspension)
        #expect(ends.receiver.poll() == nil)

        // Use elements for the background task
        let elements = ends.receiver.elements

        // Start a suspended receive
        let receiveTask = Task {
            try? await started.arrive()
            var iterator = elements.makeAsyncIterator()
            return try await iterator.next()
        }

        try? await started.arrive()

        // NOTE: We intentionally do NOT poll while receiveTask is suspended
        // because that would violate single-suspended-receiver invariant

        // Send an element
        try sender.send(42)

        // Receive should get it
        let value = try await receiveTask.value
        #expect(value == 42)
    }

    @Test
    func `Non-Sendable element exits receive() across an isolation boundary (sending result)`() async throws {
        // The receiver-side half of [MEM-SEND-010]: send() takes `consuming sending`,
        // and receive()'s `sending` result lets a non-Sendable element leave the
        // channel into another isolation domain. Proven additively in
        // swift-memory-foreign-primitives/Experiments/foreign-recycle-channel (V4);
        // this pins the canonical upstream annotation.
        final class Payload {
            var value: Int
            init(value: Int) { self.value = value }
        }
        struct Parcel: ~Copyable {
            let payload: Payload
        }
        actor Sink {
            func consume(_ parcel: consuming sending Parcel) -> Int {
                parcel.payload.value
            }
        }

        let ends = Async.Channel<Parcel>.Unbounded().take().ends()
        try ends.sender.send(Parcel(payload: Payload(value: 99)))
        ends.sender.close()
        guard let parcel = try await ends.receiver.receive() else {
            Issue.record("expected an element before close drained")
            return
        }
        // Forwarding the received value into actor isolation is what the `sending`
        // result newly permits — without it, the result merges with the receiver's
        // region and this send is rejected.
        let sink = Sink()
        let received = await sink.consume(parcel)
        #expect(received == 99)
    }
}
