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

// Async broadcast requires task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

import Dictionary_Primitives
import Queue_Primitives
import Synchronization

extension Async {
    /// Multi-reader broadcast channel with cancellation support.
    ///
    /// Provides a single-producer, multi-consumer channel where each subscriber
    /// receives all messages sent after their subscription. Messages are delivered
    /// in order to all subscribers.
    ///
    /// ## Pattern
    /// - Single producer calls `send(_:)` (synchronous, never blocks)
    /// - Multiple consumers call `subscribe()` to get a subscription
    /// - Each subscription receives all messages sent after subscription
    ///
    /// ## Delivery Guarantees
    /// - Per-subscriber ordering is guaranteed for delivered items
    /// - Slow subscribers may miss events if they fall behind the replay window
    /// - `buffer.limit` defines the replay window (default 64)
    /// - Cursor advances when element is delivered (resumed). If subscriber is
    ///   cancelled after resumption, it may not observe that element.
    ///
    /// ## Cancellation Safety
    /// When a task is cancelled while waiting in `next()`:
    /// - The operation throws `Error.cancelled`
    /// - Cancelled tasks always make progress (no deadlock)
    /// - Token matching ensures exactly-once resumption
    ///
    /// ## Performance Invariants
    /// - `buffer.first(where:)` is O(buffer.count), acceptable with limit=64
    /// - `cursor` scans subscribers O(n), acceptable for typical subscriber counts
    ///
    /// ## Concurrency
    /// - Multiple concurrent `next()` calls on same subscription: precondition failure
    ///   (single waiter per subscription enforced by precondition)
    ///
    /// ## Usage
    /// ```swift
    /// let broadcast = Async.Broadcast<Message>()
    ///
    /// // Create subscriptions before sending
    /// let sub1 = broadcast.subscribe()
    /// let sub2 = broadcast.subscribe()
    ///
    /// // Producer
    /// broadcast.send(message)
    /// broadcast.finish()
    ///
    /// // Consumers (independent tasks)
    /// for await msg in sub1 {
    ///     process(msg)
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// All operations are protected by an internal mutex.
    /// All stored properties are `let` and `Sendable` (`Mutex` provides internal synchronization).
    ///
    /// ## Cancellation (§5.3 Compliant)
    /// - Uses token-matching cancel function which returns resumption
    /// - Satisfies §5.3: "call a function that returns continuations to resume"
    /// - Single-slot waiter, token proves ownership, exactly-once provable
    public final class Broadcast<Element: Sendable>: Sendable {
        let _state: Async.Mutex<State>
        private let buffer: Buffer

        /// Creates a new broadcast channel.
        ///
        /// - Parameter bufferCapacity: Maximum number of elements to buffer for late subscribers.
        ///   Elements are discarded when the buffer is full and all subscribers have consumed them.
        public init(bufferCapacity: Int = 64) {
            precondition(bufferCapacity > 0, "Broadcast buffer capacity must be greater than zero")
            self.buffer = Buffer(limit: bufferCapacity)
            self._state = Async.Mutex(State())
        }

    }
}

// MARK: - Send

extension Async.Broadcast {
    /// Send an element to all subscribers.
    ///
    /// If a subscriber is awaiting, delivers immediately.
    /// Otherwise, buffers the element for later consumption.
    ///
    /// After `finish()`, sends are silently ignored.
    ///
    /// - Parameter element: The element to broadcast.
    public func send(_ element: sending Element) {
        let bufferLimit = buffer.limit
        let continuationsToResume: [(CheckedContinuation<Next.Outcome, Never>, Element)] = _state.withLock { state in
            guard state.is == .active else { return [] }

            let index = state.next.index
            state.next.index += 1

            // Add to buffer
            state.buffer.back.push((index, element))

            // Trim buffer if needed (keep elements that some subscriber hasn't seen yet)
            let minCursor = state.cursor ?? index
            while state.buffer.count > bufferLimit {
                if let front = state.buffer.peek.front, front.index < minCursor {
                    _ = state.buffer.front.take
                } else {
                    break
                }
            }

            // Find waiting subscribers (forEach avoids key snapshot heap allocation)
            var toResume: [(CheckedContinuation<Next.Outcome, Never>, Element)] = []
            var wakeIds: [UInt64] = []
            state.subscribers.forEach { id, subscriber in
                if subscriber.cursor == index, subscriber.continuation != nil {
                    wakeIds.append(id)
                }
            }

            // Update woken subscriber state (O(1) lookup per subscriber)
            for id in wakeIds {
                if var subscriber = state.subscribers[id] {
                    if let cont = subscriber.continuation {
                        subscriber.cursor = index + 1
                        subscriber.continuation = nil
                        state.subscribers[id] = subscriber
                        toResume.append((cont, element))
                    }
                }
            }
            return toResume
        }

        for (continuation, element) in continuationsToResume {
            continuation.resume(returning: .element(element))
        }
    }

    /// Signal that no more elements will be sent.
    ///
    /// After this call:
    /// - All pending receives return remaining buffered elements, then `nil`
    /// - Future `send()` calls are silently ignored
    public func finish() {
        let continuationsToResume: [CheckedContinuation<Next.Outcome, Never>] = _state.withLock { state in
            state.is = .finished

            // Find subscribers to finish (forEach avoids key snapshot heap allocation)
            var toResume: [CheckedContinuation<Next.Outcome, Never>] = []
            var finishIds: [UInt64] = []
            state.subscribers.forEach { id, subscriber in
                if subscriber.continuation != nil {
                    let hasBufferedElement = state.buffer.contains { $0.index >= subscriber.cursor }
                    if !hasBufferedElement {
                        finishIds.append(id)
                    }
                }
            }

            // Collect continuations and clear state
            for id in finishIds {
                if var subscriber = state.subscribers[id] {
                    if let cont = subscriber.continuation {
                        subscriber.continuation = nil
                        state.subscribers[id] = subscriber
                        toResume.append(cont)
                    }
                }
            }
            return toResume
        }

        for continuation in continuationsToResume {
            continuation.resume(returning: .finished)
        }
    }

    /// Whether `finish()` has been called.
    public var isFinished: Bool {
        _state.withLock { $0.is == .finished }
    }
}

// MARK: - Subscribe

extension Async.Broadcast {
    /// Create a new subscription starting from the current position.
    ///
    /// The subscription will receive all elements sent after this call.
    ///
    /// - Returns: A subscription that can be iterated asynchronously.
    public func subscribe() -> Subscription {
        let id = _state.withLock { state -> UInt64 in
            state.subscriber.seed += 1
            let id = state.subscriber.seed
            let cursor = state.next.index
            state.subscribers[id] = Subscriber(cursor: cursor, continuation: nil)
            return id
        }
        return Subscription(broadcast: self, id: id)
    }

}

#endif  // !hasFeature(Embedded)
