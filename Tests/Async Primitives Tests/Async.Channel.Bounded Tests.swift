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

@Suite("Async.Channel.Bounded")
struct BoundedChannelTests {

    @Test("Send and receive single element")
    func sendReceiveSingleElement() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        try await sender.send(42)
        sender.close()
        let value = try await receiver.receive()
        #expect(value == 42)
    }

    @Test("Send succeeds when channel has space")
    func sendSucceeds() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 10)
        try await sender.send(42)
        sender.close()
        _ = try await receiver.receive()
    }

    @Test("Closed channel rejects send")
    func closedChannelRejectsSend() async {
        let (sender, _) = Async.Channel<Int>.Bounded.create(capacity: 1)
        sender.close()
        do {
            try await sender.send(42)
            Issue.record("Expected send to throw .closed")
        } catch .closed {
            // Expected
        } catch {
            Issue.record("Expected .closed but got \(error)")
        }
    }

    @Test("Try send returns false when full")
    func trySendReturnsFalseWhenFull() async {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let first = sender.trySend(1)
        let second = sender.trySend(2)
        #expect(first == true)
        #expect(second == false)
        _ = receiver.tryReceive()
    }

    @Test("Receive returns nil after close and drain")
    func receiveReturnsNilAfterCloseAndDrain() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 10)
        try await sender.send(1)
        try await sender.send(2)
        sender.close()

        let first = try await receiver.receive()
        let second = try await receiver.receive()
        let third = try await receiver.receive()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == nil)
    }

    @Test("Try receive returns nil when empty")
    func tryReceiveReturnsNilWhenEmpty() {
        let (_, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let result = receiver.tryReceive()
        #expect(result == nil)
    }

    @Test("Try receive returns element when available")
    func tryReceiveReturnsElement() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        try await sender.send(42)
        let result = receiver.tryReceive()
        #expect(result == 42)
    }

    @Test("isClosed reflects state")
    func isClosedReflectsState() {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        #expect(sender.isClosed == false)
        #expect(receiver.isClosed == false)
        sender.close()
        #expect(sender.isClosed == true)
        #expect(receiver.isClosed == true)
    }

    @Test("Receive suspends until element available")
    func receiveSuspendsUntilElement() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let started = Async.Barrier(parties: 2)

        let receiveTask = Task {
            await started.arrive()
            return try await receiver.receive()
        }

        await started.arrive()
        try await sender.send(42)

        let result = try await receiveTask.value
        #expect(result == 42)
    }

    @Test("Receive resumes with nil on close")
    func receiveResumesOnClose() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let started = Async.Barrier(parties: 2)

        let receiveTask = Task {
            await started.arrive()
            return try await receiver.receive()
        }

        await started.arrive()
        sender.close()

        let result = try await receiveTask.value
        #expect(result == nil)
    }

    @Test("Send suspends when buffer is full")
    func sendSuspendsWhenFull() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let started = Async.Barrier(parties: 2)

        try await sender.send(1)

        let sendTask = Task {
            await started.arrive()
            try await sender.send(2)
        }

        await started.arrive()

        let first = try await receiver.receive()
        #expect(first == 1)

        try await sendTask.value

        let second = try await receiver.receive()
        #expect(second == 2)
    }

    @Test("Close cancels pending sends")
    func closeCancelsPendingSends() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let started = Async.Barrier(parties: 2)

        try await sender.send(1)

        let sendTask = Task { () -> Async.Channel<Int>.Error? in
            await started.arrive()
            do {
                try await sender.send(2)
                return nil
            } catch let error as Async.Channel<Int>.Error {
                return error
            } catch {
                return nil
            }
        }

        await started.arrive()
        sender.close()

        let error = await sendTask.value
        #expect(error == .closed)

        _ = try await receiver.receive()
    }

    @Test("Backpressure maintains order")
    func backpressureMaintainsOrder() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 2)

        let producer = Task {
            for i in 1...5 {
                try await sender.send(i)
            }
            sender.close()
        }

        var received: [Int] = []
        while let value = try await receiver.receive() {
            received.append(value)
        }

        try await producer.value

        #expect(received == [1, 2, 3, 4, 5])
    }

    @Test("Direct delivery when receiver waiting")
    func directDeliveryWhenReceiverWaiting() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 1)
        let started = Async.Barrier(parties: 2)

        let receiveTask = Task {
            await started.arrive()
            return try await receiver.receive()
        }

        await started.arrive()
        try await sender.send(42)

        let result = try await receiveTask.value
        #expect(result == 42)
    }

    @Test("Elements iteration")
    func elementsIteration() async throws {
        let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 10)
        try await sender.send(1)
        try await sender.send(2)
        try await sender.send(3)
        sender.close()

        var received: [Int] = []
        for try await value in receiver.elements {
            received.append(value)
        }

        #expect(received == [1, 2, 3])
    }

    @Test("Auto-close when sender drops")
    func autoCloseWhenSenderDrops() async throws {
        let receiver: Async.Channel<Int>.Bounded.Receiver
        do {
            let (sender, recv) = Async.Channel<Int>.Bounded.create(capacity: 1)
            receiver = recv
            try await sender.send(42)
            // sender drops here
        }

        let value = try await receiver.receive()
        #expect(value == 42)

        #expect(receiver.isClosed == true)

        let nilValue = try await receiver.receive()
        #expect(nilValue == nil)
    }

    @Test("Sender copies share storage")
    func senderCopiesShareStorage() async throws {
        let (sender1, receiver) = Async.Channel<Int>.Bounded.create(capacity: 10)
        let sender2 = sender1

        try await sender1.send(1)
        try await sender2.send(2)

        sender1.close()

        let first = try await receiver.receive()
        let second = try await receiver.receive()
        let third = try await receiver.receive()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == nil)
    }
}
