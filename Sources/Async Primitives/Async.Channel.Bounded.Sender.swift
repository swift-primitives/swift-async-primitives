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

internal import Queue_Primitives

extension Async.Channel.Bounded {
    /// A sender handle for a bounded channel.
    ///
    /// `Sender` is a Copyable, Sendable struct that allows sending elements
    /// to a bounded channel. Multiple senders can share the same channel
    /// by copying the handle (each copy shares the underlying storage).
    ///
    /// When the last `Sender` copy is dropped (all references released),
    /// the channel automatically closes, waking any waiting receivers.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Bounded(capacity: 10)
    ///
    /// // Send elements (may suspend if buffer full)
    /// try await channel.sender.send(42)
    ///
    /// // Clone sender for another producer (ARC increments)
    /// let sender2 = channel.sender
    ///
    /// // Close explicitly (or let auto-close on last drop)
    /// channel.close()
    /// ```
    ///
    /// ## Thread Safety
    /// `Sender` is `Sendable` and can be shared across tasks/actors.
    public struct Sender: Sendable {
        @usableFromInline
        let handle: Handle

        @usableFromInline
        init(storage: Storage) {
            self.handle = Handle(storage: storage)
        }
    }
}

// MARK: - Handle (ARC-based auto-close)

extension Async.Channel.Bounded.Sender {
    /// Internal handle that provides ARC-based auto-close.
    ///
    /// When the last reference to this handle is released, the channel
    /// automatically closes.
    @usableFromInline
    final class Handle: @unchecked Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
            self.storage = storage
        }

        deinit {
            // Auto-close when last sender drops
            var closeAction = storage.withLock { state in
                state.close()
            }

            // Resume receiver with nil (channel closed) - outside lock
            unsafe closeAction.receiverToResume?.resume(returning: (nil, nil))

            // Cancel all waiting senders - outside lock
            while let continuation = unsafe closeAction.sendersToCancel.take.front {
                unsafe continuation.resume(returning: .closed)
            }
        }
    }
}

// MARK: - Send Operations

extension Async.Channel.Bounded.Sender {
    /// Send an element to the channel.
    ///
    /// Suspends if the buffer is full until space becomes available
    /// or the channel is closed.
    ///
    /// - Parameters:
    ///   - element: The element to send.
    ///   - isolation: The actor isolation context for the operation.
    ///
    /// - Throws: `Async.Channel<Element>.Error.closed` if the channel is closed.
    ///           `Async.Channel<Element>.Error.cancelled` if the task is cancelled.
    @inlinable
    public func send(
        _ element: Element,
        isolation: isolated (any Actor)? = #isolation
    ) async throws(Async.Channel<Element>.Error) {
        // Fast path: try immediate send
        let fastAction = handle.storage.withLock { state in
            state.trySend(element)
        }

        switch fastAction {
        case .deliverToReceiver(let receiverCont, let element):
            unsafe receiverCont.resume(returning: (element, nil))
            return
        case .buffered:
            return
        case .rejectClosed:
            throw .closed
        case .rejectCancelled:
            throw .cancelled
        case .suspend:
            break // Fall through to slow path
        }

        // Slow path: need to suspend
        let id = handle.storage.withLock { state in
            state.generateId()
        }

        let error: Async.Channel<Element>.Error? = await withTaskCancellationHandler {
            await withUnsafeContinuation { (continuation: UnsafeContinuation<Async.Channel<Element>.Error?, Never>) in
                let action = handle.storage.withLock { state in
                    state.sendSuspended(id: id, element: element, continuation: continuation)
                }

                switch action {
                case .deliverToReceiver(let receiverCont, let element):
                    unsafe receiverCont.resume(returning: (element, nil))
                    unsafe continuation.resume(returning: nil)
                case .buffered:
                    unsafe continuation.resume(returning: nil)
                case .rejectClosed:
                    unsafe continuation.resume(returning: .closed)
                case .rejectCancelled:
                    unsafe continuation.resume(returning: .cancelled)
                case .suspend:
                    // Continuation stored, will be resumed later
                    break
                }
            }
        } onCancel: {
            let action = handle.storage.withLock { state in
                state.sendCancelled(id: id)
            }
            switch action {
            case .resumeWithCancellation(let continuation):
                unsafe continuation.resume(returning: .cancelled)
            case .none:
                break
            }
        }

        if let error { throw error }
    }

    /// Accessor for send operation variants.
    public var send: Send { Send(handle: handle) }
}

// MARK: - Send Accessor

extension Async.Channel.Bounded.Sender {
    /// Send operation accessor with variants.
    public struct Send: Sendable {
        @usableFromInline
        let handle: Handle

        @usableFromInline
        init(handle: Handle) {
            self.handle = handle
        }

        /// Send an element without suspending.
        ///
        /// - Parameter element: The element to send.
        /// - Throws: `.full` if the buffer is full, `.closed` if the channel is closed,
        ///           `.cancelled` if the task was cancelled.
        @inlinable
        public func immediate(_ element: Element) throws(Async.Channel<Element>.Error) {
            let action = handle.storage.withLock { state in
                state.trySend(element)
            }

            switch action {
            case .deliverToReceiver(let receiverCont, let element):
                unsafe receiverCont.resume(returning: (element, nil))
            case .buffered:
                break
            case .rejectClosed:
                throw .closed
            case .rejectCancelled:
                throw .cancelled
            case .suspend:
                throw .full
            }
        }
    }
}

// MARK: - Lifecycle

extension Async.Channel.Bounded.Sender {
    /// Close the channel, signaling no more elements will be sent.
    ///
    /// After this call:
    /// - Any pending `receive()` returns `nil` (if buffer empty)
    /// - Future `receive()` calls drain buffer then return `nil`
    /// - Future `send()` calls throw `Error.closed`
    /// - Pending `send()` calls throw `Error.closed`
    public func close() {
        var closeAction = handle.storage.withLock { state in
            state.close()
        }

        // Resume receiver with nil (channel closed) - outside lock
        unsafe closeAction.receiverToResume?.resume(returning: (nil, nil))

        // Cancel all waiting senders - outside lock
        while let continuation = unsafe closeAction.sendersToCancel.take.front {
            unsafe continuation.resume(returning: .closed)
        }
    }

    /// Whether the channel has been closed.
    ///
    /// Note: Even when `true`, `receive()` may still return elements
    /// if the buffer is not yet drained.
    public var isClosed: Bool {
        handle.storage.withLock { $0.isClosed }
    }
}

#endif  // !hasFeature(Embedded)
