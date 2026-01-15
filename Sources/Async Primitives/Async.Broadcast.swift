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

import Container_Primitives
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
    /// - `minCursor()` scans subscribers O(n), acceptable for typical subscriber counts
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
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    ///
    /// ## Cancellation (§5.3 Compliant)
    /// - Uses token-matching cancel function which returns resumption
    /// - Satisfies §5.3: "call a function that returns continuations to resume"
    /// - Single-slot waiter, token proves ownership, exactly-once provable
    public final class Broadcast<Element: Sendable>: @unchecked Sendable {
        private let _state: Mutex<State>
        private let buffer: Buffer

        /// Creates a new broadcast channel.
        ///
        /// - Parameter bufferCapacity: Maximum number of elements to buffer for late subscribers.
        ///   Elements are discarded when the buffer is full and all subscribers have consumed them.
        public init(bufferCapacity: Int = 64) {
            precondition(bufferCapacity > 0, "Broadcast buffer capacity must be greater than zero")
            self.buffer = Buffer(limit: bufferCapacity)
            self._state = Mutex(State())
        }

        /// Buffer configuration namespace.
        struct Buffer {
            let limit: Int
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
    public func send(_ element: Element) {
        let continuationsToResume: [(CheckedContinuation<Next.Outcome, Never>, Element)] = _state.withLock { state in
            guard !state.is.finished else { return [] }

            let index = state.next.index
            state.next.index += 1

            // Add to buffer
            state.buffer.push.back((index, element))

            // Trim buffer if needed (keep elements that some subscriber hasn't seen yet)
            let minCursor = state.minCursor() ?? index
            while state.buffer.count > buffer.limit {
                if let front = state.buffer.peek.front, front.index < minCursor {
                    _ = state.buffer.take.front
                } else {
                    break
                }
            }

            // Find and wake up waiting subscribers (snapshot iteration)
            var toResume: [(CheckedContinuation<Next.Outcome, Never>, Element)] = []
            let ids = Array(state.subscribers.keys)
            for id in ids {
                guard var subscriber = state.subscribers[id] else { continue }
                if subscriber.cursor == index, let cont = subscriber.continuation {
                    subscriber.cursor = index + 1
                    subscriber.continuation = nil
                    state.subscribers[id] = subscriber
                    toResume.append((cont, element))
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
            state.is.finished = true

            // Wake up all waiting subscribers with .finished if they've consumed everything (snapshot iteration)
            var toResume: [CheckedContinuation<Next.Outcome, Never>] = []
            let ids = Array(state.subscribers.keys)
            for id in ids {
                guard var subscriber = state.subscribers[id] else { continue }
                if let cont = subscriber.continuation {
                    // Check if there are buffered elements for this subscriber
                    let hasBufferedElement = state.buffer.contains { $0.index >= subscriber.cursor }
                    if !hasBufferedElement {
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
        _state.withLock { $0.is.finished }
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

    /// A subscription to a broadcast channel.
    ///
    /// Conforms to `AsyncSequence` for use in `for await` loops.
    /// Each subscription maintains independent cursor position.
    public struct Subscription: Sendable, AsyncSequence {
        let broadcast: Async.Broadcast<Element>
        let id: UInt64

        init(broadcast: Async.Broadcast<Element>, id: UInt64) {
            self.broadcast = broadcast
            self.id = id
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(broadcast: broadcast, id: id)
        }

        /// Unsubscribe and release resources.
        public func cancel() {
            let continuationToCancel: CheckedContinuation<Next.Outcome, Never>? = broadcast._state.withLock { state in
                guard let subscriber = state.subscribers.values.remove(id) else { return nil }
                return subscriber.continuation
            }
            continuationToCancel?.resume(returning: .finished)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            let broadcast: Async.Broadcast<Element>
            let id: UInt64

            public mutating func next() async throws(Async.Broadcast<Element>.Error) -> Element? {
                // Capture values explicitly to avoid capturing self in @Sendable closures
                let broadcast = self.broadcast
                let id = self.id

                // Publication slot for cancellation-safe token publication/claim
                let publication = Async.Publication<Wait>()

                let result: Next.Outcome = await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        // Single lock acquisition: returns immediate result OR installed wait token
                        let (immediateResult, installedWait): (Next.Outcome?, Wait?) = broadcast._state.withLock { state in
                            guard var subscriber = state.subscribers[id] else {
                                return (.finished, nil)
                            }

                            // Check for buffered element
                            if let entry = state.buffer.first(where: { $0.index == subscriber.cursor }) {
                                subscriber.cursor += 1
                                state.subscribers[id] = subscriber
                                return (.element(entry.element), nil)
                            }

                            // Check if finished
                            if state.is.finished {
                                return (.finished, nil)
                            }

                            // Must suspend - allocate token
                            // Precondition: no concurrent next() on same subscription
                            precondition(subscriber.continuation == nil,
                                "Broadcast: concurrent next() calls on same subscription")
                            subscriber.wait.token &+= 1
                            let token = subscriber.wait.token
                            subscriber.continuation = continuation
                            state.subscribers[id] = subscriber
                            return (nil, Wait(token: token))
                        }

                        if let result = immediateResult {
                            continuation.resume(returning: result)
                            return
                        }

                        // Publish the wait token (returned from same lock acquisition)
                        if let w = installedWait {
                            publication.publish(w)

                            // Close the early-cancellation window:
                            // If task was cancelled after install but before onCancel could see the token,
                            // we must perform cancellation here.
                            if Task.isCancelled {
                                if let taken = publication.take() {
                                    // §5.3: funnel through cancel(subscriber:token:)
                                    let cancelled = broadcast._state.withLock { state in
                                        state.cancel(subscriber: id, token: taken.token)
                                    }
                                    cancelled?.resume(returning: .cancelled)
                                    return  // Exit immediately after cancellation resume
                                }
                            }
                        }
                        // Otherwise continuation stored, will be resumed by send/finish/cancel
                    }
                } onCancel: { [publication, broadcast, id] in
                    // Atomically take the published token
                    guard let taken = publication.take() else { return }

                    // §5.3: Call cancel(subscriber:token:) which uses token matching.
                    // This guarantees progress - cancelled task always resumes.
                    let cancelled = broadcast._state.withLock { state in
                        state.cancel(subscriber: id, token: taken.token)
                    }

                    // Resume cancelled subscriber outside lock (if token matched)
                    cancelled?.resume(returning: .cancelled)
                }

                switch result {
                case .element(let e): return e
                case .finished: return nil
                case .cancelled: throw .cancelled
                }
            }
        }
    }
}

#endif  // !hasFeature(Embedded)
