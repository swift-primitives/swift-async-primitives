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
    import Dictionary_Ordered_Primitives
    import Queue_Primitives
    import Queue_DoubleEnded_Primitives

    extension Async.Broadcast {
        /// Internal state machine for the broadcast channel.
        struct State {
            /// Buffer of (index, element) pairs for replay.
            var buffer: Deque<(index: UInt64, element: Element)> = .init()

            /// Next element index to assign.
            var next: Next.Index = .init()

            /// Active subscribers keyed by ID.
            var subscribers: Dictionary<UInt64, Subscriber>.Ordered = .init()

            /// Subscriber ID allocation.
            var subscriber: Subscriber.ID = .init()

            /// Lifecycle flags.
            var `is`: Is = .active
        }

    }

    // MARK: - Buffer Management

    extension Async.Broadcast.State {
        /// Minimum cursor position across all subscribers.
        ///
        /// O(n) where n = subscriber count — acceptable for typical usage.
        var cursor: UInt64? {
            subscribers.values.map(\.cursor).min()
        }
    }

    // MARK: - Cancellation Funnel (§5.3 Compliant)

    extension Async.Broadcast.State {
        /// Single resumption funnel for cancellation path.
        ///
        /// Uses token matching to prove ownership of the wait slot.
        /// Returns continuation to resume if token matches, otherwise nil.
        ///
        /// ## §5.3 Compliance
        /// This satisfies §5.3 ("call a function that returns resumptions"):
        /// - Single-slot waiter per subscriber - no pump/queue complexity needed
        /// - Token matching proves ownership; exactly-once provable by construction
        /// - The cancel function is the "funnel" - it decides outcome and returns resumption
        ///
        /// - Parameters:
        ///   - subscriberID: The subscriber to cancel.
        ///   - token: The wait token to match.
        /// - Returns: Continuation to resume with .cancelled, or nil if token mismatch.
        mutating func cancel(
            subscriber subscriberID: UInt64,
            token: UInt64
        ) -> CheckedContinuation<Async.Broadcast<Element>.Next.Outcome, Never>? {
            guard var subscriber = subscribers[subscriberID] else { return nil }

            // Token matching: only clear if our token matches
            guard subscriber.wait.token == token,
                let cont = subscriber.continuation
            else { return nil }

            subscriber.continuation = nil
            // Do NOT advance cursor - element not delivered
            subscribers[subscriberID] = subscriber
            return cont
        }
    }

#endif  // !hasFeature(Embedded)
