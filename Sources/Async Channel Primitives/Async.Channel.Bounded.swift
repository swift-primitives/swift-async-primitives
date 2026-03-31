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

extension Async.Channel where Element: ~Copyable {
    /// Bounded channel with backpressure.
    ///
    /// Provides a capacity-limited channel where sends suspend when
    /// the buffer is full (backpressure) and receives suspend when empty.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Bounded(capacity: 10)
    ///
    /// // Producer task (Sender is Copyable, Sendable)
    /// Task {
    ///     try await channel.sender.send(1)
    ///     try await channel.sender.send(2)
    ///     channel.close()
    /// }
    ///
    /// // Consumer (single task, Receiver enforces single-consumer)
    /// for try await value in channel.receiver.elements {
    ///     print(value)
    /// }
    /// ```
    ///
    /// ## Design
    /// - `Bounded` is `~Copyable` - channel identity cannot be duplicated
    /// - `sender` is `Copyable` - can be shared across tasks
    /// - `receiver` is `~Copyable` - exactly one receiver per channel
    /// - Auto-close: Channel closes when last Sender drops
    ///
    /// ## Error Handling
    /// Operations use typed throws for exhaustive error handling:
    /// ```swift
    /// do {
    ///     try await channel.sender.send(value)
    /// } catch .closed {
    ///     // Channel was closed
    /// } catch .cancelled {
    ///     // Task was cancelled
    /// }
    /// ```
    public struct Bounded: ~Copyable, Sendable {
        @usableFromInline
        let storage: Storage

        /// View for sending elements to this channel.
        ///
        /// `Sender` is `Copyable` - multiple sender views can exist,
        /// and they all share the same underlying channel.
        /// Channel auto-closes when the last Sender reference drops.
        public let sender: Sender

        /// View for receiving elements from this channel.
        ///
        /// `Receiver` is `~Copyable` - exactly one receiver exists per channel.
        /// This enforces single-receiver semantics at the type level.
        public var receiver: Receiver

        /// Creates a new bounded channel with the specified capacity.
        ///
        /// - Parameter capacity: The maximum number of elements that can be buffered.
        ///   Must be greater than zero.
        public init(capacity: Index<Element>.Count) {
            precondition(capacity > .zero, "Bounded channel capacity must be greater than zero")
            let storage = Storage(capacity: capacity)
            self.storage = storage
            self.sender = Sender(storage: storage)
            self.receiver = Receiver(storage: storage)
        }
    }
}

extension Async.Channel.Bounded where Element: ~Copyable {
    /// Close the channel, signaling no more elements will be sent.
    ///
    /// After close:
    /// - `send()` throws `.closed`
    /// - `receive()` drains buffer then returns `nil`
    public func close() {
        sender.close()
    }

    /// Whether the channel has been closed.
    public var isClosed: Bool {
        storage.withLock { $0.isClosed }
    }
}

// MARK: - Take (consuming accessors)

extension Async.Channel.Bounded where Element: ~Copyable {
    /// Consuming accessor for moving endpoints out of the channel.
    ///
    /// ```swift
    /// let ends = channel.take().ends()
    /// try await ends.sender.send(42)
    /// let value = try await ends.receiver.receive()
    /// ```
    public consuming func take() -> Take {
        Take(channel: consume self)
    }
}

#endif  // !hasFeature(Embedded)
