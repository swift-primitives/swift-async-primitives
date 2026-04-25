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

enum Core {
    enum Test {
        @Suite struct Lifecycle {}
        @Suite struct Precedence {}
        @Suite struct Promise {}
        @Suite struct Barrier {}
        #if !hasFeature(Embedded)
        @Suite struct Completion {}
        #endif
    }
}

// MARK: - Lifecycle Tests

extension Core.Test.Lifecycle {
    @Test
    func `open state has correct queries`() {
        var state: Async.Lifecycle.State = .open
        #expect(state.isOpen)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(!isActive)
        #expect(!isComplete)
    }

    @Test
    func `closing state has correct queries`() {
        var state: Async.Lifecycle.State = .closing
        #expect(!state.isOpen)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(isActive)
        #expect(!isComplete)
    }

    @Test
    func `closed state has correct queries`() {
        var state: Async.Lifecycle.State = .closed
        #expect(!state.isOpen)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(isActive)
        #expect(isComplete)
    }

    @Test
    func `shutdown begin transitions open to closing`() {
        var state: Async.Lifecycle.State = .open
        let result = state.shutdown.begin()
        #expect(result)
        #expect(state == .closing)
    }

    @Test
    func `shutdown begin is idempotent on closing`() {
        var state: Async.Lifecycle.State = .closing
        let result = state.shutdown.begin()
        #expect(!result)
        #expect(state == .closing)
    }

    @Test
    func `shutdown begin is idempotent on closed`() {
        var state: Async.Lifecycle.State = .closed
        let result = state.shutdown.begin()
        #expect(!result)
        #expect(state == .closed)
    }

    @Test
    func `shutdown complete transitions closing to closed`() {
        var state: Async.Lifecycle.State = .closing
        let result = state.shutdown.complete()
        #expect(result)
        #expect(state == .closed)
    }

    @Test
    func `shutdown complete is idempotent on open`() {
        var state: Async.Lifecycle.State = .open
        let result = state.shutdown.complete()
        #expect(!result)
        #expect(state == .open)
    }

    @Test
    func `shutdown complete is idempotent on closed`() {
        var state: Async.Lifecycle.State = .closed
        let result = state.shutdown.complete()
        #expect(!result)
        #expect(state == .closed)
    }

    @Test
    func `full lifecycle open to closing to closed`() {
        var state: Async.Lifecycle.State = .open
        #expect(state.isOpen)

        let didBegin = state.shutdown.begin()
        #expect(didBegin)
        #expect(state == .closing)
        let isActive = state.shutdown.isActive
        let isComplete = state.shutdown.isComplete
        #expect(isActive)
        #expect(!isComplete)

        let didComplete = state.shutdown.complete()
        #expect(didComplete)
        #expect(state == .closed)
        let finalComplete = state.shutdown.isComplete
        #expect(finalComplete)
    }

    @Test
    func `cannot skip closing state`() {
        var state: Async.Lifecycle.State = .open
        // Cannot go directly from open to closed
        let result = state.shutdown.complete()
        #expect(!result)
        #expect(state == .open)
    }
}

// MARK: - Precedence Tests

extension Core.Test.Precedence {
    @Test
    func `shutdown dominates all`() {
        let result = Async.Precedence.resolve(
            shutdown: true,
            cancelled: true,
            timedOut: true,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "shutdown")
    }

    @Test
    func `cancelled dominates timeout and success`() {
        let result = Async.Precedence.resolve(
            shutdown: false,
            cancelled: true,
            timedOut: true,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "cancelled")
    }

    @Test
    func `timedOut dominates success`() {
        let result = Async.Precedence.resolve(
            shutdown: false,
            cancelled: false,
            timedOut: true,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "timeout")
    }

    @Test
    func `success when nothing is set`() {
        let result = Async.Precedence.resolve(
            shutdown: false,
            cancelled: false,
            timedOut: false,
            success: "success",
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "success")
    }

    @Test
    func `autoclosure lazily evaluates success outcome`() {
        var evaluated = false
        let result = Async.Precedence.resolve(
            shutdown: true,
            cancelled: false,
            timedOut: false,
            success: { evaluated = true; return "success" }(),
            onShutdown: "shutdown",
            onCancelled: "cancelled",
            onTimeout: "timeout"
        )
        #expect(result == "shutdown")
        #expect(!evaluated)
    }
}

// MARK: - Promise Tests

extension Core.Test.Promise {
    @Test
    func `init creates unfulfilled promise`() {
        let promise = Async.Promise<Int>()
        #expect(!promise.isFulfilled)
        #expect(promise.fulfilled == nil)
    }

    @Test
    func `value() does not observe Task cancellation`() async {
        // Pins the documented contract: Promise.value() is non-observing
        // by signature (async -> Value, not throws). A cancelled Task
        // awaiting value() still resumes with the fulfilled value.
        let promise = Async.Promise<Int>()

        let task = Task { await promise.value() }

        // Let the task suspend on value()
        try? await Task.sleep(for: .milliseconds(20))

        // Cancel the awaiter — should NOT interrupt value()
        task.cancel()

        // Give cancellation time to propagate (it shouldn't, but we test that)
        try? await Task.sleep(for: .milliseconds(20))

        // Fulfill — every waiter (including the cancelled task) resumes
        #expect(promise.fulfill(42))

        let result = await task.value
        #expect(result == 42, "cancelled awaiter still receives the fulfilled value")
        #expect(task.isCancelled, "task should still report itself as cancelled")
    }

    @Test
    func `fulfill sets value and returns true`() {
        let promise = Async.Promise<Int>()
        let result = promise.fulfill(42)
        #expect(result)
        #expect(promise.isFulfilled)
        #expect(promise.fulfilled == 42)
    }

    @Test
    func `double fulfill returns false`() {
        let promise = Async.Promise<Int>()
        #expect(promise.fulfill(1))
        #expect(!promise.fulfill(2))
        // First value wins
        #expect(promise.fulfilled == 1)
    }

    @Test
    func `wait callback invoked immediately when fulfilled`() {
        let promise = Async.Promise<Int>()
        promise.fulfill(42)

        let publication = Async.Publication<Int>()
        promise.wait { value in
            publication.publish(value)
        }
        #expect(publication.take() == 42)
    }

    @Test
    func `wait callback deferred until fulfill`() {
        let promise = Async.Promise<Int>()

        let publication = Async.Publication<Int>()
        promise.wait { value in
            publication.publish(value)
        }

        // Not yet fulfilled
        #expect(publication.take() == nil)

        // Fulfill triggers callback
        promise.fulfill(99)
        #expect(publication.take() == 99)
    }

    @Test
    func `multiple waiters all receive value`() {
        let promise = Async.Promise<Int>()

        let pub1 = Async.Publication<Int>()
        let pub2 = Async.Publication<Int>()
        let pub3 = Async.Publication<Int>()

        promise.wait { pub1.publish($0) }
        promise.wait { pub2.publish($0) }
        promise.wait { pub3.publish($0) }

        promise.fulfill(7)

        #expect(pub1.take() == 7)
        #expect(pub2.take() == 7)
        #expect(pub3.take() == 7)
    }

    @Test
    func `gate open and wait`() {
        let gate = Async.Gate()
        #expect(!gate.isOpen)

        let publication = Async.Publication<Bool>()
        gate.wait {
            publication.publish(true)
        }
        #expect(publication.take() == nil)

        #expect(gate.open())
        #expect(gate.isOpen)
        #expect(publication.take() == true)
    }

    @Test
    func `gate double open returns false`() {
        let gate = Async.Gate()
        #expect(gate.open())
        #expect(!gate.open())
    }

    #if !hasFeature(Embedded)
    @Test
    func `async value returns fulfilled value`() async {
        let promise = Async.Promise<Int>()
        promise.fulfill(42)
        let value = await promise.value()
        #expect(value == 42)
    }

    @Test
    func `async gate wait returns after open`() async {
        let gate = Async.Gate()
        gate.open()
        await gate.wait()
        // If we reach here, wait returned correctly
    }
    #endif
}

// MARK: - Barrier Tests

extension Core.Test.Barrier {
    @Test
    func `init creates unreleased barrier`() {
        let barrier = Async.Barrier(parties: 3)
        #expect(barrier.arrived == 0)
        #expect(!barrier.isReleased)
    }

    @Test
    func `single party barrier releases immediately`() {
        let barrier = Async.Barrier(parties: 1)

        let publication = Async.Publication<Bool>()
        barrier.arrive {
            publication.publish(true)
        }
        #expect(publication.take() == true)
        #expect(barrier.isReleased)
        #expect(barrier.arrived == 1)
    }

    @Test
    func `multi party barrier waits for all arrivals`() {
        let barrier = Async.Barrier(parties: 3)

        let pub1 = Async.Publication<Bool>()
        let pub2 = Async.Publication<Bool>()
        let pub3 = Async.Publication<Bool>()

        barrier.arrive { pub1.publish(true) }
        #expect(pub1.take() == nil)
        #expect(barrier.arrived == 1)
        #expect(!barrier.isReleased)

        barrier.arrive { pub2.publish(true) }
        #expect(pub2.take() == nil)
        #expect(barrier.arrived == 2)
        #expect(!barrier.isReleased)

        // Last party triggers all callbacks
        barrier.arrive { pub3.publish(true) }
        #expect(pub1.take() == true)
        #expect(pub2.take() == true)
        #expect(pub3.take() == true)
        #expect(barrier.arrived == 3)
        #expect(barrier.isReleased)
    }

    @Test
    func `arrive after release invokes callback immediately`() {
        let barrier = Async.Barrier(parties: 1)
        barrier.arrive { }

        let publication = Async.Publication<Bool>()
        barrier.arrive { publication.publish(true) }
        #expect(publication.take() == true)
    }

    #if !hasFeature(Embedded)
    @Test
    func `async arrive releases when all parties arrive`() async {
        let barrier = Async.Barrier(parties: 3)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await barrier.arrive()
                }
            }
        }

        #expect(barrier.isReleased)
        #expect(barrier.arrived == 3)
    }
    #endif
}

// MARK: - Completion Tests

#if !hasFeature(Embedded)
extension Core.Test.Completion {
    @Test
    func `init creates pending state`() {
        let completion = Async.Completion<Int, Never>()
        #expect(completion.state == .pending)
        #expect(!completion.isTerminal)
    }

    @Test
    func `start transitions to running`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        #expect(completion.state == .running)
        #expect(!completion.isTerminal)
    }

    @Test
    func `complete transitions to completed`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        try completion.complete(42)
        #expect(completion.state == .completed)
        #expect(completion.isTerminal)
    }

    @Test
    func `timeout transitions to timedOut`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        try completion.timeout()
        #expect(completion.state == .timedOut)
        #expect(completion.isTerminal)
    }

    @Test
    func `cancel from pending transitions to cancelled`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.cancel()
        #expect(completion.state == .cancelled)
        #expect(completion.isTerminal)
    }

    @Test
    func `cancel from running transitions to cancelled`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        try completion.cancel()
        #expect(completion.state == .cancelled)
        #expect(completion.isTerminal)
    }

    @Test
    func `double start throws`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        do {
            try completion.start()
            Issue.record("Expected alreadyDone error")
        } catch {
            // Transition.Error.alreadyDone — expected
        }
    }

    @Test
    func `complete without start throws`() {
        let completion = Async.Completion<Int, Never>()
        do {
            try completion.complete(42)
            Issue.record("Expected alreadyDone error")
        } catch {
            // Expected — complete requires running state
        }
    }

    @Test
    func `timeout without start throws`() {
        let completion = Async.Completion<Int, Never>()
        do {
            try completion.timeout()
            Issue.record("Expected alreadyDone error")
        } catch {
            // Expected — timeout requires running state
        }
    }

    @Test
    func `cancel from completed throws`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        try completion.complete(42)
        do {
            try completion.cancel()
            Issue.record("Expected alreadyDone error")
        } catch {
            // Expected — already in terminal state
        }
    }

    @Test
    func `complete after timeout throws`() throws {
        let completion = Async.Completion<Int, Never>()
        try completion.start()
        try completion.timeout()
        do {
            try completion.complete(99)
            Issue.record("Expected alreadyDone error")
        } catch {
            // Expected — already timed out
        }
    }

    @Test
    func `fail from pending transitions to failed`() {
        let completion = Async.Completion<Int, TestError>()
        do {
            try completion.fail(.testFailure)
            #expect(completion.state == .failed)
            #expect(completion.isTerminal)
        } catch {
            Issue.record("Unexpected error")
        }
    }

    @Test
    func `fail from running throws`() throws {
        let completion = Async.Completion<Int, TestError>()
        try completion.start()
        do {
            try completion.fail(.testFailure)
            Issue.record("Expected alreadyDone error")
        } catch {
            // Expected — fail only works from pending
        }
    }

    @Test
    func `full lifecycle with continuation`() async {
        let completion = Async.Completion<Int, Never>()

        let result = await withCheckedContinuation { continuation in
            completion.set(continuation: continuation)
            try! completion.start()
            try! completion.complete(42)
        }

        if case .success(let value) = result {
            #expect(value == 42)
        } else {
            Issue.record("Expected success result")
        }
    }

    @Test
    func `cancellation delivers cancellation error`() async {
        let completion = Async.Completion<Int, Never>()

        let result = await withCheckedContinuation { continuation in
            completion.set(continuation: continuation)
            try! completion.start()
            try! completion.cancel()
        }

        if case .failure(.cancelled) = result {
            // Expected
        } else {
            Issue.record("Expected cancelled error, got \(result)")
        }
    }

    @Test
    func `timeout delivers timeout error`() async {
        let completion = Async.Completion<Int, Never>()

        let result = await withCheckedContinuation { continuation in
            completion.set(continuation: continuation)
            try! completion.start()
            try! completion.timeout()
        }

        if case .failure(.timeout) = result {
            // Expected
        } else {
            Issue.record("Expected timeout error, got \(result)")
        }
    }
}

// MARK: - Test Helpers

private enum TestError: Error, Sendable {
    case testFailure
}
#endif
