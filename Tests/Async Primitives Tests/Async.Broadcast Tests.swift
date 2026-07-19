// W5-3 QUARANTINE (2026-06-11): rides the parked Async_Broadcast_Primitives target — see Package.swift.
// The canImport gate self-restores when the target returns with its round.
#if canImport(Async_Broadcast_Primitives)
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
    struct BroadcastTests {

        @Test
        func `Single subscriber receives all elements`() async throws {
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()

            broadcast.send(1)
            broadcast.send(2)
            broadcast.send(3)
            broadcast.finish()

            var received: [Int] = []
            for try await value in subscription {
                received.append(value)
            }

            #expect(received == [1, 2, 3])
        }

        @Test
        func `Multiple subscribers each receive all elements`() async throws {
            let broadcast = Async.Broadcast<Int>()
            let sub1 = broadcast.subscribe()
            let sub2 = broadcast.subscribe()

            broadcast.send(1)
            broadcast.send(2)
            broadcast.finish()

            let task1 = Task {
                var received: [Int] = []
                for try await value in sub1 {
                    received.append(value)
                }
                return received
            }

            let task2 = Task {
                var received: [Int] = []
                for try await value in sub2 {
                    received.append(value)
                }
                return received
            }

            let result1 = try await task1.value
            let result2 = try await task2.value

            #expect(result1 == [1, 2])
            #expect(result2 == [1, 2])
        }

        @Test
        func `Late subscriber only sees new elements`() async throws {
            let broadcast = Async.Broadcast<Int>()

            broadcast.send(1)

            let subscription = broadcast.subscribe()

            broadcast.send(2)
            broadcast.send(3)
            broadcast.finish()

            var received: [Int] = []
            for try await value in subscription {
                received.append(value)
            }

            #expect(received == [2, 3])
        }

        @Test
        func `isFinished reflects state`() {
            let broadcast = Async.Broadcast<Int>()
            #expect(broadcast.isFinished == false)
            broadcast.finish()
            #expect(broadcast.isFinished == true)
        }

        @Test
        func `Subscriber suspends until element available`() async throws {
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()
            let started = Async.Barrier(parties: 2)

            // Start receive in background
            let receiveTask = Task { () -> Int? in
                try? await started.arrive()  // Signal ready
                var iterator = subscription.makeAsyncIterator()
                return try await iterator.next()
            }

            // Wait for task to be ready
            try? await started.arrive()

            // Send element
            broadcast.send(42)

            // Receive should complete with the element
            let result = try await receiveTask.value
            #expect(result == 42)
        }

        @Test
        func `Subscriber resumes with nil on finish`() async throws {
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()
            let started = Async.Barrier(parties: 2)

            // Start receive in background
            let receiveTask = Task { () -> Int? in
                try? await started.arrive()  // Signal ready
                var iterator = subscription.makeAsyncIterator()
                return try await iterator.next()
            }

            // Wait for task to be ready
            try? await started.arrive()

            // Finish broadcast
            broadcast.finish()

            // Receive should complete with nil
            let result = try await receiveTask.value
            #expect(result == nil)
        }

        @Test
        func `Cancel subscription stops iteration`() async throws {
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()
            let started = Async.Barrier(parties: 2)

            // Start receive in background
            let receiveTask = Task { () -> Int? in
                try? await started.arrive()  // Signal ready
                var iterator = subscription.makeAsyncIterator()
                return try await iterator.next()
            }

            // Wait for task to be ready
            try? await started.arrive()

            // Cancel subscription
            subscription.cancel()

            // Receive should complete with nil
            let result = try await receiveTask.value
            #expect(result == nil)
        }

        @Test
        func `Elements delivered in order`() async throws {
            // Explicit buffer capacity: this test is pinning ordering, not
            // replay-window/drop behavior — the subscriber is only drained
            // after all 100 sends, so an explicit capacity >= the element
            // count keeps it out of the (correctly, per F-002) trimmed path.
            let broadcast = Async.Broadcast<Int>(bufferCapacity: 100)
            let subscription = broadcast.subscribe()

            for i in 1...100 {
                broadcast.send(i)
            }
            broadcast.finish()

            var received: [Int] = []
            for try await value in subscription {
                received.append(value)
            }

            #expect(received == Array(1...100))
        }

        @Test
        func `Send after finish is ignored`() async throws {
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()

            broadcast.send(1)
            broadcast.finish()
            broadcast.send(2)  // Should be ignored

            var received: [Int] = []
            for try await value in subscription {
                received.append(value)
            }

            #expect(received == [1])
        }

        @Test
        func `Task cancellation throws cancelled error`() async {
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()
            let started = Async.Barrier(parties: 2)

            let receiveTask = Task {
                try? await started.arrive()  // Signal ready
                var iterator = subscription.makeAsyncIterator()
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
            } catch let error as Async.Broadcast<Int>.Error {
                #expect(error == .cancelled)
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - Stress Tests

    @Suite
    struct BroadcastStressTests {

        /// Yield multiple times to allow concurrent tasks to make progress.
        private func yieldProgress(iterations: Int = 50) async {
            for _ in 0..<iterations {
                await Task.yield()
            }
        }

        @Test
        func `All subscribers receive all elements - no loss`() async throws {
            // Multiple subscribers, all should receive every element.
            // This tests the core broadcast invariant.
            for round in 0..<20 {
                let elementCount = 50
                // Explicit buffer capacity to ensure no trimming affects this test
                let broadcast = Async.Broadcast<Int>(bufferCapacity: elementCount)
                let subscriberCount = 5

                // Create subscriptions before sending
                let subscriptions = (0..<subscriberCount).map { _ in
                    broadcast.subscribe()
                }

                // Start consumer tasks
                let consumerTasks = subscriptions.map { subscription in
                    Task {
                        var received: [Int] = []
                        for try await value in subscription {
                            received.append(value)
                        }
                        return received
                    }
                }

                // Yield to let consumers start
                await yieldProgress(iterations: 20)

                // Send all elements
                for i in 0..<elementCount {
                    broadcast.send(i)
                }
                broadcast.finish()

                // Collect results from all subscribers
                for (index, task) in consumerTasks.enumerated() {
                    let received = try await task.value

                    // Each subscriber must receive all elements in exact order
                    #expect(
                        received.count == elementCount,
                        "Round \(round), subscriber \(index): count \(received.count) != \(elementCount)"
                    )
                    #expect(
                        received == Array(0..<elementCount),
                        "Round \(round), subscriber \(index): elements mismatch"
                    )
                }
            }
        }

        @Test
        func `Cancellation racing with send - token matching correctness`() async throws {
            // Force cancelled subscribers to be in "waiting state" when cancelled.
            // Non-cancelled subscribers must still receive all elements.
            for round in 0..<30 {
                let elementCount = 20
                let broadcast = Async.Broadcast<Int>(bufferCapacity: elementCount)
                let subscriberCount = 10

                let subscriptions = (0..<subscriberCount).map { _ in
                    broadcast.subscribe()
                }

                // Start consumer tasks
                let consumerTasks = subscriptions.enumerated().map { index, subscription in
                    Task {
                        var received: [Int] = []
                        var iterator = subscription.makeAsyncIterator()
                        while true {
                            do {
                                guard let value = try await iterator.next() else {
                                    break  // Finished
                                }
                                received.append(value)
                            } catch let error as Async.Broadcast<Int>.Error {
                                #expect(
                                    error == .cancelled,
                                    "Round \(round), subscriber \(index): Expected .cancelled, got \(error)"
                                )
                                return (index, received, true)  // cancelled
                            } catch {
                                #expect(Bool(false), "Round \(round), subscriber \(index): Unexpected error: \(error)")
                                break
                            }
                        }
                        return (index, received, false)  // not cancelled
                    }
                }

                // Step 1: Send first element so everyone consumes one
                broadcast.send(0)
                await yieldProgress(iterations: 30)

                // Step 2: Now subscribers are waiting in next() for element 1
                // Cancel even-indexed subscribers while they are suspended
                for i in stride(from: 0, to: subscriberCount, by: 2) {
                    consumerTasks[i].cancel()
                }

                // Step 3: Send remaining elements
                for i in 1..<elementCount {
                    broadcast.send(i)
                    await Task.yield()
                }
                broadcast.finish()

                // Collect results
                var cancelledCount = 0
                for task in consumerTasks {
                    let (index, received, wasCancelled) = await task.value

                    if wasCancelled {
                        cancelledCount += 1
                        // Cancelled subscribers should have received element 0 before cancellation
                        #expect(
                            received.first == 0 || received.isEmpty,
                            "Round \(round), cancelled subscriber \(index): Unexpected first element"
                        )
                    } else {
                        // Non-cancelled subscribers must have all elements in exact order
                        #expect(
                            received == Array(0..<elementCount),
                            "Round \(round), subscriber \(index): Expected all elements"
                        )
                    }
                }

                // At least some cancellations should have occurred
                #expect(cancelledCount > 0, "Round \(round): No cancellations observed")
            }
        }

        @Test
        func `Finish racing with pending subscribers - all resume with nil`() async throws {
            // Subscribers created after sends, then finish() called.
            // All must resume with empty results (no hang).
            for round in 0..<30 {
                let broadcast = Async.Broadcast<Int>()
                let subscriberCount = 15
                let preBufferedCount = 5

                // Pre-send some elements (subscribers created after won't see these)
                for i in 0..<preBufferedCount {
                    broadcast.send(i)
                }

                // Create subscriptions (cursor starts after pre-sent elements)
                let subscriptions = (0..<subscriberCount).map { _ in
                    broadcast.subscribe()
                }

                // Start consumers
                let consumerTasks = subscriptions.map { subscription in
                    Task { () -> [Int] in
                        var received: [Int] = []
                        for try await value in subscription {
                            received.append(value)
                        }
                        return received
                    }
                }

                // Yield to let them start waiting
                await yieldProgress()

                // Finish immediately (no more elements after subscription)
                broadcast.finish()

                // All must complete with empty results (no hang, no error)
                for (index, task) in consumerTasks.enumerated() {
                    let received = try await task.value
                    // Subscriptions created after send() see nothing
                    #expect(
                        received.isEmpty,
                        "Round \(round), subscriber \(index): Expected empty, got \(received.count) elements"
                    )
                }
            }
        }

        @Test
        func `Many subscribers with interleaved send and cancel`() async throws {
            // Pure integrity stress test under concurrent send, subscribe, and cancel.
            //
            // INVARIANTS validated (must hold regardless of scheduling):
            // - Elements received in strict monotonic order (no reordering)
            // - No duplicate elements within any subscriber
            // - All values within expected range [0, elementCount)
            // - Every subscriber terminates (normally OR via .cancelled)
            //
            // NOT validated here (timing-dependent):
            // - Whether cancellation is observed (may complete normally before cancel propagates)
            // - How many subscribers observe cancellation
            //
            // Cancellation semantics correctness is validated deterministically
            // in cancellationRacingWithSend via explicit token matching.
            let subscriberCount = 20
            let elementCount = 500
            let broadcast = Async.Broadcast<Int>(bufferCapacity: elementCount)

            let results = Async.Channel<(id: Int, elements: [Int], terminatedViaCancellation: Bool)>.Unbounded().take().ends()

            var subscriberTasks: [(id: Int, task: Task<Void, Never>)] = []

            for id in 0..<subscriberCount {
                let task = Task { [sender = results.sender] in
                    let subscription = broadcast.subscribe()
                    var received: [Int] = []
                    var terminatedViaCancellation = false

                    var iterator = subscription.makeAsyncIterator()
                    loop: while true {
                        do {
                            guard let value = try await iterator.next() else {
                                break loop  // Normal finish
                            }
                            received.append(value)
                            await Task.yield()
                        } catch let error as Async.Broadcast<Int>.Error {
                            // Explicit check: only .cancelled is expected from broadcast
                            #expect(
                                error == .cancelled,
                                "Subscriber \(id): Unexpected broadcast error: \(error)"
                            )
                            terminatedViaCancellation = true
                            break loop
                        } catch {
                            // Unexpected error type - this IS a test failure
                            #expect(Bool(false), "Subscriber \(id): Unexpected error type: \(error)")
                            break loop
                        }
                    }

                    do { try sender.send((id: id, elements: received, terminatedViaCancellation: terminatedViaCancellation)) } catch { #expect(Bool(false), "results channel unexpectedly closed") }
                }
                subscriberTasks.append((id: id, task: task))
            }

            let idsToCancel = Set(stride(from: 0, to: subscriberCount, by: 3))

            await withTaskGroup(of: Void.self) { group in
                // Producer: high throughput with periodic yields
                group.addTask {
                    for i in 0..<elementCount {
                        broadcast.send(i)
                        if i % 20 == 0 { await Task.yield() }
                    }
                    broadcast.finish()
                }

                // Cancellation: yield to increase probability of overlap with active work
                group.addTask { [subscriberTasks] in
                    for _ in 0..<10 { await Task.yield() }
                    for entry in subscriberTasks where idsToCancel.contains(entry.id) {
                        entry.task.cancel()
                    }
                }

                // Await all subscribers
                group.addTask { [subscriberTasks] in
                    for entry in subscriberTasks {
                        await entry.task.value
                    }
                }
            }

            results.close()

            // Validate invariants
            var completedSubscribers = 0

            while let result = try await results.receiver.receive() {
                completedSubscribers += 1

                // INVARIANT: Strict monotonic ordering
                for i in 1..<result.elements.count {
                    #expect(
                        result.elements[i] > result.elements[i - 1],
                        "Subscriber \(result.id): Out of order at index \(i): \(result.elements[i - 1]) -> \(result.elements[i])"
                    )
                }

                // INVARIANT: No duplicates
                #expect(
                    Set(result.elements).count == result.elements.count,
                    "Subscriber \(result.id): Duplicate elements detected"
                )

                // INVARIANT: All values in range
                for value in result.elements {
                    #expect(
                        (0..<elementCount).contains(value),
                        "Subscriber \(result.id): Value \(value) out of range [0, \(elementCount))"
                    )
                }
            }

            // INVARIANT: All subscribers terminated
            #expect(
                completedSubscribers == subscriberCount,
                "Expected \(subscriberCount) subscribers to terminate, got \(completedSubscribers)"
            )
        }

        @Test
        func `Buffer trimming with slow subscriber`() async throws {
            // One slow subscriber, one fast subscriber.
            // Fast subscriber should not be blocked and gets all elements.
            // Slow subscriber may miss elements if it falls too far behind.
            let bufferCapacity = 10
            let broadcast = Async.Broadcast<Int>(bufferCapacity: bufferCapacity)
            let elementCount = 100

            let fastSub = broadcast.subscribe()
            let slowSub = broadcast.subscribe()

            // Fast consumer - no artificial delays
            let fastTask = Task {
                var received: [Int] = []
                for try await value in fastSub {
                    received.append(value)
                }
                return received
            }

            // Slow consumer - delays between reads
            let slowTask = Task {
                var received: [Int] = []
                var iterator = slowSub.makeAsyncIterator()
                while let value = try await iterator.next() {
                    received.append(value)
                    // Slow down by yielding many times
                    for _ in 0..<10 {
                        await Task.yield()
                    }
                }
                return received
            }

            // Producer
            Task {
                for i in 0..<elementCount {
                    broadcast.send(i)
                    await Task.yield()
                }
                broadcast.finish()
            }

            let fastReceived = try await fastTask.value
            let slowReceived = try await slowTask.value

            // Fast subscriber should get all elements in exact order
            #expect(
                fastReceived == Array(0..<elementCount),
                "Fast subscriber should receive all elements in order"
            )

            // Slow subscriber: strictly increasing (no out-of-order)
            for i in 1..<slowReceived.count {
                #expect(
                    slowReceived[i] > slowReceived[i - 1],
                    "Slow subscriber elements out of order at index \(i)"
                )
            }

            // No duplicates
            #expect(
                Set(slowReceived).count == slowReceived.count,
                "Slow subscriber has duplicates"
            )

            // All received elements must be in valid range
            for value in slowReceived {
                #expect(
                    (0..<elementCount).contains(value),
                    "Slow subscriber received out-of-range value: \(value)"
                )
            }
        }

        @Test
        func `Sequential next usage is correct`() async throws {
            // Demonstrates correct sequential iteration pattern.
            // (Note: Concurrent next() on same subscription is a precondition violation)
            let broadcast = Async.Broadcast<Int>()
            let subscription = broadcast.subscribe()

            // Send elements
            for i in 0..<10 {
                broadcast.send(i)
            }
            broadcast.finish()

            // Sequential iteration (correct usage)
            var received: [Int] = []
            for try await value in subscription {
                received.append(value)
            }

            #expect(received == Array(0..<10))
        }
    }

    // MARK: - F-002 Regression (generic-namespace [INST-TEST-013] carve-out)
    //
    // `Async.Broadcast<Element>` is generic, so a nested `@Suite` extension
    // of the source type would itself be uninstantiated/undiscoverable —
    // this uses the documented carve-out instead: a top-level, non-generic
    // `@Suite("Name") struct Tests`. Kept separate from the pre-existing
    // `BroadcastTests` / `BroadcastStressTests` suites above (which predate
    // this convention) rather than folding the new test into their
    // compound-name style.

    @Suite("Broadcast")
    struct Tests {
        @Test
        func `send trims the replay buffer to bufferLimit behind a stalled subscriber, which observes loss`() async throws {
            // F-002 (option a): the documented contract is that `buffer.limit`
            // is the replay window and a subscriber that falls behind it
            // observes loss (Async.Broadcast's "Delivery Guarantees" doc).
            // Pre-fix, `send()` only trimmed entries older than the SLOWEST
            // subscriber's cursor, so a subscriber that never calls next()
            // pins the buffer at its cursor forever and the buffer grows
            // without bound instead of ever dropping anything.
            let bufferLimit = 4
            let broadcast = Async.Broadcast<Int>(bufferCapacity: bufferLimit)

            // Subscribed before any sends, then never consumed until after
            // finish() — permanently "stalled" at its initial cursor.
            let stalled = broadcast.subscribe()

            let elementCount = 50
            for i in 0..<elementCount {
                broadcast.send(i)
            }
            broadcast.finish()

            var received: [Int] = []
            for try await value in stalled {
                received.append(value)
            }

            // The buffer must have been trimmed to exactly the last
            // `bufferLimit` elements, with the stalled subscriber's cursor
            // advanced past everything dropped — not every one of the 50
            // sent elements.
            #expect(received == Array((elementCount - bufferLimit)..<elementCount))
        }
    }

#endif
