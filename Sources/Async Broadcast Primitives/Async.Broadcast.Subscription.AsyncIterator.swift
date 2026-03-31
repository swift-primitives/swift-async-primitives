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

extension Async.Broadcast.Subscription {
    /// Async iterator for broadcast subscriptions.
    public struct AsyncIterator {
        let broadcast: Async.Broadcast<Element>
        let id: UInt64
        let publication: Async.Publication<Async.Broadcast<Element>.Wait>
    }
}

// MARK: - AsyncIteratorProtocol

extension Async.Broadcast.Subscription.AsyncIterator: AsyncIteratorProtocol {
    nonisolated(nonsending)
    public mutating func next() async throws(Async.Broadcast<Element>.Error) -> Element? {
        // Capture values explicitly to avoid capturing self in @Sendable closures
        let broadcast = self.broadcast
        let id = self.id

        // Reuse per-iterator publication slot; clear any stale value from previous call
        let publication = self.publication
        _ = publication.take()

        let result: Async.Broadcast<Element>.Next.Outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Single lock acquisition: returns immediate result OR installed wait token
                let (immediateResult, installedWait): (Async.Broadcast<Element>.Next.Outcome?, Async.Broadcast<Element>.Wait?) = broadcast._state.withLock { state in
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
                    if state.is == .finished {
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
                    return (nil, Async.Broadcast<Element>.Wait(token: token))
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

#endif  // !hasFeature(Embedded)
