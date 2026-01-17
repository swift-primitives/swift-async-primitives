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

// Async channels require task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

public import Container_Primitives

extension Async.Channel.Bounded {
    /// A receiver handle for a bounded channel.
    ///
    /// `Receiver` enforces a single-suspended-receiver invariant: at most one
    /// task may be suspended in `receive()` at a time. Concurrent suspended
    /// receives trigger a precondition failure in `State.receiveSuspended`.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Bounded(capacity: 10)
    ///
    /// // Receive elements (may suspend if buffer empty)
    /// while let value = try await channel.receiver.receive() {
    ///     process(value)
    /// }
    ///
    /// // Or iterate via AsyncSequence view
    /// for try await value in channel.receiver.elements {
    ///     process(value)
    /// }
    /// ```
    ///
    /// ## Thread Safety
    /// `Receiver` is `@unchecked Sendable` - it may be moved to another task
    /// for the canonical "handoff to consumer task" pattern. The mutex guards
    /// all state access. Concurrent suspension is caught by precondition.
    public struct Receiver: ~Copyable, @unchecked Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }
    }
}

// MARK: - Receive Operations

extension Async.Channel.Bounded.Receiver {
    /// Receive the next element from the channel.
    ///
    /// Suspends if the buffer is empty until an element becomes available
    /// or the channel is closed and drained.
    ///
    /// - Returns: The next element, or `nil` if the channel is closed and drained.
    /// - Throws: `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
    @inlinable
    public func receive() async throws(Async.Channel<Element>.Error) -> Element? {
        // Fast path: try immediate receive
        let fastAction = storage.withLock { state in
            state.tryReceive()
        }

        switch fastAction {
        case .returnElement(let element, let resumeSender, var cancelled):
            // Resume cancelled senders first (minimizes stuck time)
            while let c = unsafe cancelled.take.front {
                unsafe c.resume(returning: .cancelled)
            }
            unsafe resumeSender?.resume(returning: nil)
            return element
        case .returnNil:
            return nil
        case .rejectCancelled:
            throw .cancelled
        case .suspend:
            break // Fall through to slow path
        }

        // Slow path: need to suspend
        let (element, error): (Element?, Async.Channel<Element>.Error?) = await withTaskCancellationHandler {
            await withUnsafeContinuation { (continuation: UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>) in
                let action = storage.withLock { state in
                    state.receiveSuspended(continuation: continuation)
                }

                switch action {
                case .returnElement(let element, let resumeSender, var cancelled):
                    // Resume cancelled senders first (minimizes stuck time)
                    while let c = unsafe cancelled.take.front {
                        unsafe c.resume(returning: .cancelled)
                    }
                    unsafe resumeSender?.resume(returning: nil)
                    unsafe continuation.resume(returning: (element, nil))
                case .returnNil:
                    unsafe continuation.resume(returning: (nil, nil))
                case .rejectCancelled:
                    unsafe continuation.resume(returning: (nil, .cancelled))
                case .suspend:
                    // Continuation stored, will be resumed later
                    break
                }
            }
        } onCancel: {
            let action = storage.withLock { state in
                state.receiveCancelled()
            }
            switch action {
            case .resumeWithCancellation(let continuation):
                unsafe continuation.resume(returning: (nil, .cancelled))
            case .none:
                break
            }
        }

        if let error { throw error }
        return element
    }

    /// Accessor for receive operation variants.
    public var receive: Receive { Receive(storage: storage) }
}

// MARK: - Receive Accessor

extension Async.Channel.Bounded.Receiver {
    /// Receive operation accessor with variants.
    public struct Receive: @unchecked Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
            self.storage = storage
        }

        /// Receive an element without suspending.
        ///
        /// - Returns: The next element if available, `nil` if the channel is closed and drained.
        /// - Throws: `.empty` if the buffer is empty, `.cancelled` if the task was cancelled.
        @inlinable
        public func immediate() throws(Async.Channel<Element>.Error) -> Element? {
            let action = storage.withLock { state in
                state.tryReceive()
            }

            switch action {
            case .returnElement(let element, let resumeSender, var cancelled):
                // Resume cancelled senders first (minimizes stuck time)
                while let c = unsafe cancelled.take.front {
                    unsafe c.resume(returning: .cancelled)
                }
                unsafe resumeSender?.resume(returning: nil)
                return element
            case .returnNil:
                return nil
            case .rejectCancelled:
                throw .cancelled
            case .suspend:
                throw .empty
            }
        }
    }
}

// MARK: - Query

extension Async.Channel.Bounded.Receiver {
    /// Whether the channel has been closed.
    ///
    /// Note: Even when `true`, `receive()` may still return elements
    /// if the buffer is not yet drained.
    public var isClosed: Bool {
        storage.withLock { $0.isClosed }
    }
}

// MARK: - AsyncSequence View

extension Async.Channel.Bounded.Receiver {
    /// Returns an AsyncSequence view for iteration.
    ///
    /// ```swift
    /// for try await value in receiver.elements {
    ///     process(value)
    /// }
    /// ```
    public var elements: Async.Channel<Element>.Bounded.Elements {
        Async.Channel<Element>.Bounded.Elements(storage: storage)
    }
}

extension Async.Channel.Bounded {
    /// An AsyncSequence view over a bounded channel receiver.
    public struct Elements: AsyncSequence, @unchecked Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(storage: Storage) {
            self.storage = storage
        }

        public func makeAsyncIterator() -> Iterator {
            Iterator(storage: storage)
        }
    }
}

extension Async.Channel.Bounded.Elements {
    /// Iterator for the AsyncSequence view.
    public struct Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
            self.storage = storage
        }

        @inlinable
        public mutating func next() async throws(Async.Channel<Element>.Error) -> Element? {
            // Capture storage to avoid capturing self in @Sendable closure
            let storage = self.storage

            // Fast path: try immediate receive
            let fastAction = storage.withLock { state in
                state.tryReceive()
            }

            switch fastAction {
            case .returnElement(let element, let resumeSender, var cancelled):
                while let c = unsafe cancelled.take.front {
                    unsafe c.resume(returning: .cancelled)
                }
                unsafe resumeSender?.resume(returning: nil)
                return element
            case .returnNil:
                return nil
            case .rejectCancelled:
                throw .cancelled
            case .suspend:
                break
            }

            // Slow path: need to suspend
            let (element, error): (Element?, Async.Channel<Element>.Error?) = await withTaskCancellationHandler {
                await withUnsafeContinuation { (continuation: UnsafeContinuation<(Element?, Async.Channel<Element>.Error?), Never>) in
                    let action = storage.withLock { state in
                        state.receiveSuspended(continuation: continuation)
                    }

                    switch action {
                    case .returnElement(let element, let resumeSender, var cancelled):
                        while let c = unsafe cancelled.take.front {
                            unsafe c.resume(returning: .cancelled)
                        }
                        unsafe resumeSender?.resume(returning: nil)
                        unsafe continuation.resume(returning: (element, nil))
                    case .returnNil:
                        unsafe continuation.resume(returning: (nil, nil))
                    case .rejectCancelled:
                        unsafe continuation.resume(returning: (nil, .cancelled))
                    case .suspend:
                        break
                    }
                }
            } onCancel: {
                let action = storage.withLock { state in
                    state.receiveCancelled()
                }
                switch action {
                case .resumeWithCancellation(let continuation):
                    unsafe continuation.resume(returning: (nil, .cancelled))
                case .none:
                    break
                }
            }

            if let error { throw error }
            return element
        }
    }
}

#endif  // !hasFeature(Embedded)
