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
    import Deque_Primitives
    import Synchronization
    import Column_Primitives
    import Buffer_Ring_Primitive
    import Storage_Contiguous_Primitives
    import Memory_Heap_Primitives
    import Memory_Allocator_Primitive
    import Buffer_Primitive

    extension Async {
        /// A thread-safe bridge for sync-to-async element handoff.
        ///
        /// Bridge provides a multi-producer, single-consumer channel for
        /// transferring elements from synchronous code (e.g., OS threads)
        /// to async code (e.g., Swift actors).
        ///
        /// Supports `~Copyable` elements. The continuation is a void signal —
        /// elements are always delivered through the internal buffer, never
        /// through the continuation return value. This is required because
        /// `CheckedContinuation<T>` requires `T: Copyable`.
        ///
        /// ## Performance
        /// - Fast path (buffer non-empty): single mutex acquisition
        /// - Slow path (suspension → wakeup): three mutex acquisitions,
        ///   dominated by the task suspension/context-switch cost
        ///
        /// ## Pattern
        /// - Producers call `push(_:)` (synchronous, never blocks)
        /// - Consumer calls `next()` (async, suspends until element available)
        ///
        /// ## Single-Consumer Invariant
        /// Only one task may call `next()` at a time. Concurrent `next()` calls
        /// result in undefined behavior (debug builds trigger a precondition failure).
        ///
        /// ## Cancellation
        /// `next()` does NOT observe Task cancellation — its non-throwing
        /// `async -> Element?` signature precludes it. A consumer Task
        /// cancelled while suspended in `next()` continues to suspend until
        /// `push(_:)` or `finish()` signals; if the producer never signals,
        /// the awaiter never resumes. Termination is the producer's
        /// responsibility (call `finish()` when done).
        ///
        /// Composers needing cancellation-aware bridge consumption MUST
        /// arrange external cancellation — e.g. wrap `next()` in a
        /// `withTaskCancellationHandler` block and call `finish()` from the
        /// onCancel handler, or carry an explicit cancellation flag the
        /// producer side polls.
        ///
        /// ## No Lifecycle Policy
        /// The bridge has minimal semantics - `finish()` signals no more values
        /// will be pushed, and `next()` returns `nil` when finished AND drained.
        /// Higher layers compose shutdown behavior using `CPU.Atomic.Flag`.
        ///
        /// ## Thread Safety
        /// All operations are protected by an internal mutex.
        /// All stored properties are `let` and `Sendable` (`Mutex` provides internal synchronization).
        public final class Bridge<Element: ~Copyable & Sendable>: Sendable {
            private let _state: Async.Mutex<State>

            private enum _Take: ~Copyable {
                case element(Element)
                case finished
                case suspend
            }

            struct State: ~Copyable {
                var buffer: Deque<Column.Ring<Element>> = .init()
                var continuation: CheckedContinuation<Void, Never>?
                var isFinished: Bool = false
                #if DEBUG
                    var hasWaitingConsumer: Bool = false
                #endif
            }

            /// Creates a new bridge.
            public init() {
                self._state = Async.Mutex(State())
            }
        }
    }

    // MARK: - Core Operations

    extension Async.Bridge where Element: ~Copyable {
        /// Push a single element from a sync context.
        ///
        /// Always buffers the element, then signals any waiting consumer.
        ///
        /// After `finish()`, pushes are silently ignored (element is dropped).
        ///
        /// - Parameter element: The element to deliver (ownership transferred
        ///   across isolation boundary).
        public func push(_ element: consuming sending Element) {
            let continuationToResume: CheckedContinuation<Void, Never>? =
                _state.withLock(consuming: element) { state, element in
                    guard !state.isFinished else {
                        _ = consume element
                        return nil
                    }
                    state.buffer.push(consume element, to: .back)
                    if let cont = state.continuation {
                        state.continuation = nil
                        #if DEBUG
                            state.hasWaitingConsumer = false
                        #endif
                        return cont
                    }
                    return nil
                }
            continuationToResume?.resume()
        }

        /// Wait for the next element (async, suspends if none available).
        ///
        /// Fast path (buffer non-empty or finished): single mutex acquisition,
        /// no task suspension. Slow path (empty buffer, not finished): suspends
        /// until `push()` or `finish()` signals.
        ///
        /// - Returns: The next element, or `nil` if finished AND drained.
        ///
        /// - Important: Only one task may call `next()` at a time.
        ///   Concurrent calls result in undefined behavior.
        nonisolated(nonsending)
            public func next() async -> Element?
        {
            // Fast path: try to take from buffer under single lock
            let fast: _Take = _state.withLock { state in
                #if DEBUG
                    precondition(
                        !state.hasWaitingConsumer,
                        "Bridge: concurrent next() calls detected - single-consumer invariant violated"
                    )
                #endif

                if let element = state.buffer.pop(from: .front) {
                    return .element(element)
                }
                if state.isFinished {
                    return .finished
                }
                return .suspend
            }

            switch consume fast {
            case .element(let element):
                return element
            case .finished:
                return nil
            case .suspend:
                break
            }

            // Slow path: suspend until push() or finish() signals
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let shouldResumeImmediately: Bool = _state.withLock { state in
                    // Re-check: producer may have pushed between the fast-path lock and here
                    if !state.buffer.isEmpty || state.isFinished {
                        return true
                    }
                    state.continuation = continuation
                    #if DEBUG
                        state.hasWaitingConsumer = true
                    #endif
                    return false
                }
                if shouldResumeImmediately {
                    continuation.resume()
                }
            }

            // After signal: take from buffer
            return _state.withLock { state in
                #if DEBUG
                    state.hasWaitingConsumer = false
                #endif
                return state.buffer.pop(from: .front)
            }
        }

        /// Signal that no more elements will be pushed.
        ///
        /// After this call:
        /// - Any pending `next()` is signaled (returns `nil` if buffer empty)
        /// - Future `next()` calls drain buffer then return `nil`
        /// - Future `push()` calls are silently ignored
        public func finish() {
            let continuationToResume: CheckedContinuation<Void, Never>? = _state.withLock { state in
                state.isFinished = true
                if let cont = state.continuation {
                    state.continuation = nil
                    #if DEBUG
                        state.hasWaitingConsumer = false
                    #endif
                    return cont
                }
                return nil
            }
            continuationToResume?.resume()
        }

        /// Whether `finish()` has been called.
        ///
        /// Note: Even when `true`, `next()` may still return elements
        /// if the buffer is not yet drained.
        public var isFinished: Bool {
            _state.withLock { $0.isFinished }
        }
    }

    // MARK: - Batch Push (~Copyable)

    extension Async.Bridge where Element: ~Copyable {
        /// Push elements by draining a source from a sync context.
        ///
        /// Calls `next` repeatedly inside a single lock acquisition until
        /// it returns `nil`. All elements are buffered before signaling
        /// any waiting consumer.
        ///
        /// After `finish()`, pushes are silently ignored and the source
        /// is not drained.
        ///
        /// ```swift
        /// bridge.push { source.front.take }
        /// ```
        ///
        /// - Parameter next: A closure that produces the next element,
        ///   or `nil` when the source is exhausted.
        public func push(draining next: () -> Element?) {
            let continuationToResume: CheckedContinuation<Void, Never>? = _state.withLock { state in
                guard !state.isFinished else { return nil }
                while let element = next() {
                    state.buffer.push(consume element, to: .back)
                }
                if let cont = state.continuation {
                    state.continuation = nil
                    #if DEBUG
                        state.hasWaitingConsumer = false
                    #endif
                    return cont
                }
                return nil
            }
            continuationToResume?.resume()
        }
    }

    // MARK: - Batch Push (Copyable)

    extension Async.Bridge where Element: Copyable {
        /// Push multiple elements from a sync context (fast path).
        ///
        /// Efficiently transfers a batch without per-element overhead.
        /// If the consumer is awaiting, signals it after buffering all elements.
        ///
        /// After `finish()`, pushes are silently ignored.
        ///
        /// - Parameter elements: The elements to deliver.
        public func push(_ elements: borrowing [Element]) {
            guard !elements.isEmpty else { return }

            let continuationToResume: CheckedContinuation<Void, Never>? = _state.withLock { state in
                guard !state.isFinished else { return nil }
                for i in 0..<elements.count {
                    state.buffer.push(elements[i], to: .back)
                }
                if let cont = state.continuation {
                    state.continuation = nil
                    #if DEBUG
                        state.hasWaitingConsumer = false
                    #endif
                    return cont
                }
                return nil
            }
            continuationToResume?.resume()
        }

        /// Push elements from a sequence.
        ///
        /// Iterates the sequence inside the lock — no intermediate Array
        /// allocation. The lock is held for the duration of iteration.
        ///
        /// After `finish()`, pushes are silently ignored.
        ///
        /// - Parameter elements: The elements to deliver.
        public func push<S: Swift.Sequence>(contentsOf elements: S) where S.Element == Element {
            let continuationToResume: CheckedContinuation<Void, Never>? = _state.withLock { state in
                guard !state.isFinished else { return nil }
                for element in elements {
                    state.buffer.push(element, to: .back)
                }
                if let cont = state.continuation {
                    state.continuation = nil
                    #if DEBUG
                        state.hasWaitingConsumer = false
                    #endif
                    return cont
                }
                return nil
            }
            continuationToResume?.resume()
        }
    }

#endif  // !hasFeature(Embedded)
