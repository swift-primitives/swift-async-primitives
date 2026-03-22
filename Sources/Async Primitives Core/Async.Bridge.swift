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

// Async.Bridge provides sync-to-async handoff using withCheckedContinuation.
// This is inherently async-only and not available on embedded Swift.
#if !hasFeature(Embedded)

import Queue_Primitives
import Synchronization

extension Async {
    /// A thread-safe bridge for sync-to-async element handoff.
    ///
    /// Bridge provides a multi-producer, single-consumer channel for
    /// transferring elements from synchronous code (e.g., OS threads)
    /// to async code (e.g., Swift actors).
    ///
    /// ## Pattern
    /// - Producers call `push(_:)` (synchronous, never blocks)
    /// - Consumer calls `next()` (async, suspends until element available)
    ///
    /// ## Single-Consumer Invariant
    /// Only one task may call `next()` at a time. Concurrent `next()` calls
    /// result in undefined behavior (debug builds trigger a precondition failure).
    ///
    /// ## No Lifecycle Policy
    /// The bridge has minimal semantics - `finish()` signals no more values
    /// will be pushed, and `next()` returns `nil` when finished AND drained.
    /// Higher layers compose shutdown behavior using `Kernel.Atomic.Flag`.
    ///
    /// ## Usage
    /// ```swift
    /// let bridge = Async.Bridge<Int>()
    ///
    /// // Producer (sync thread)
    /// bridge.push(1)
    /// bridge.push([2, 3, 4])
    /// bridge.finish()
    ///
    /// // Consumer (async)
    /// while let value = await bridge.next() {
    ///     // Process value
    /// }
    /// // nil means finished AND drained
    /// ```
    ///
    /// ## Thread Safety
    /// All operations are protected by an internal mutex.
    /// Uses `@unchecked Sendable` because internal state is protected
    /// by mutex synchronization.
    public final class Bridge<Element: Sendable>: @unchecked Sendable {
        private let _state: Mutex<State>

        struct State {
            var buffer: Deque<Element> = .init()
            var continuation: CheckedContinuation<Element?, Never>?
            var isFinished: Bool = false
            #if DEBUG
            var hasWaitingConsumer: Bool = false
            #endif
        }

        /// Creates a new bridge.
        public init() {
            self._state = Mutex(State())
        }

        /// Push a single element from a sync context.
        ///
        /// If the consumer is awaiting via `next()`, resumes it immediately.
        /// Otherwise, queues the element for later consumption.
        ///
        /// After `finish()`, pushes are silently ignored.
        ///
        /// - Parameter element: The element to deliver.
        public func push(_ element: sending Element) {
            let continuationToResume: CheckedContinuation<Element?, Never>? = _state.withLock { state in
                Self._pushLocked(&state, element)
            }
            continuationToResume?.resume(returning: element)
        }

        // WORKAROUND: @_optimize(none) here because closures are separate SIL functions
        // and cannot be annotated directly. The Property.View accessor chain
        // (buffer.back.push) triggers a CopyPropagation false positive inside closures.
        // TRACKING: swift-buffer-primitives/Research/rawlayout-release-crash-investigation.md (Bug 2)
        @_optimize(none)
        private static func _pushLocked(
            _ state: inout State, _ element: Element
        ) -> CheckedContinuation<Element?, Never>? {
            guard !state.isFinished else { return nil }
            if let cont = state.continuation {
                state.continuation = nil
                #if DEBUG
                state.hasWaitingConsumer = false
                #endif
                return cont
            } else {
                state.buffer.back.push(element)
                return nil
            }
        }

        /// Push multiple elements from a sync context (fast path).
        ///
        /// Efficiently transfers a batch without per-element overhead.
        /// If the consumer is awaiting, resumes with the first element
        /// and queues the rest.
        ///
        /// After `finish()`, pushes are silently ignored.
        ///
        /// - Parameter elements: The elements to deliver.
        public func push(_ elements: borrowing [Element]) {
            guard !elements.isEmpty else { return }

            // Copy indices/count outside lock to work with borrowing
            let count = elements.count
            let first = elements[0]

            let (continuationToResume, firstElement): (CheckedContinuation<Element?, Never>?, Element?) =
                _state.withLock { state in
                    Self._pushBatchLocked(&state, elements, count: count, first: first)
                }
            if let cont = continuationToResume, let element = firstElement {
                cont.resume(returning: element)
            }
        }

        // WORKAROUND: Same as _pushLocked — closures can't have @_optimize(none).
        // TRACKING: swift-buffer-primitives/Research/rawlayout-release-crash-investigation.md (Bug 2)
        @_optimize(none)
        private static func _pushBatchLocked(
            _ state: inout State,
            _ elements: borrowing [Element],
            count: Int,
            first: Element
        ) -> (CheckedContinuation<Element?, Never>?, Element?) {
            guard !state.isFinished else { return (nil, nil) }
            if let cont = state.continuation {
                state.continuation = nil
                #if DEBUG
                state.hasWaitingConsumer = false
                #endif
                // Resume with first, queue rest
                if count > 1 {
                    for i in 1..<count {
                        state.buffer.back.push(elements[i])
                    }
                }
                return (cont, first)
            } else {
                for i in 0..<count {
                    state.buffer.back.push(elements[i])
                }
                return (nil, nil)
            }
        }

        /// Push elements from a sequence.
        ///
        /// Convenience method that may internally buffer the sequence.
        /// For known arrays, prefer `push(_: [Element])` for better performance.
        ///
        /// After `finish()`, pushes are silently ignored.
        ///
        /// - Parameter elements: The elements to deliver.
        public func push<S: Swift.Sequence>(contentsOf elements: S) where S.Element == Element {
            push(Swift.Array(elements))
        }

        /// Wait for the next element (async, suspends if none available).
        ///
        /// - Parameters:
        ///   - isolation: The actor isolation context for the operation.
        ///
        /// - Returns: The next element, or `nil` if finished AND drained.
        ///
        /// - Important: Only one task may call `next()` at a time.
        ///   Concurrent calls result in undefined behavior.
        public func next(
            isolation: isolated (any Actor)? = #isolation
        ) async -> Element? {
            // Using (shouldSuspend: Bool, element: Element?) to avoid nested enum in generic
            return await withCheckedContinuation { continuation in
                let (shouldSuspend, immediateResult): (Bool, Element??) = _state.withLock { state in
                    #if DEBUG
                    precondition(
                        !state.hasWaitingConsumer,
                        "Bridge: concurrent next() calls detected - single-consumer invariant violated"
                    )
                    #endif

                    if let element = state.buffer.front.take {
                        return (false, .some(element))
                    }
                    if state.isFinished {
                        return (false, .some(nil))
                    }
                    state.continuation = continuation
                    #if DEBUG
                    state.hasWaitingConsumer = true
                    #endif
                    return (true, nil)
                }

                if !shouldSuspend {
                    continuation.resume(returning: immediateResult ?? nil)
                }
                // If shouldSuspend, will be resumed by push() or finish()
            }
        }

        /// Signal that no more elements will be pushed.
        ///
        /// After this call:
        /// - Any pending `next()` returns `nil` (if buffer empty)
        /// - Future `next()` calls drain buffer then return `nil`
        /// - Future `push()` calls are silently ignored
        public func finish() {
            let continuationToResume: CheckedContinuation<Element?, Never>? = _state.withLock { state in
                state.isFinished = true
                if let cont = state.continuation, state.buffer.isEmpty {
                    state.continuation = nil
                    #if DEBUG
                    state.hasWaitingConsumer = false
                    #endif
                    return cont
                }
                return nil
            }
            continuationToResume?.resume(returning: nil)
        }

        /// Whether `finish()` has been called.
        ///
        /// Note: Even when `true`, `next()` may still return elements
        /// if the buffer is not yet drained.
        public var isFinished: Bool {
            _state.withLock { $0.isFinished }
        }
    }
}

#endif  // !hasFeature(Embedded)
