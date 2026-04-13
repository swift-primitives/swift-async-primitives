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
    /// Unbounded channel with single-suspended-receiver semantics.
    ///
    /// Provides an unbounded-capacity channel where sends are synchronous
    /// (never suspend) and receives may suspend when the buffer is empty.
    ///
    /// ## Usage
    /// ```swift
    /// var channel = Async.Channel<Int>.Unbounded()
    ///
    /// // Producer task
    /// Task {
    ///     try channel.sender.send(1)
    ///     try channel.sender.send(2)
    ///     channel.close()
    /// }
    ///
    /// // Consumer (single-suspended-receiver)
    /// while let value = try await channel.receiver.receive() {
    ///     print(value)
    /// }
    /// ```
    ///
    /// ## Design
    /// - `Unbounded` is `~Copyable` - channel identity cannot be duplicated
    /// - `sender` is `Copyable` - can be shared across tasks
    /// - `receiver` is `~Copyable` - exactly one receiver per channel
    /// - Single-suspended-receiver is both type-enforced (one receiver) and
    ///   runtime-enforced (precondition on concurrent suspension)
    ///
    /// ## Lifecycle
    /// - Close via explicit `close()` or `sender.close()`
    /// - Implicit close when storage is released (last reference drops)
    /// - Dropping `Sender` views has no lifecycle effect
    ///
    /// ## Error Handling
    /// Operations use typed throws for exhaustive error handling:
    /// ```swift
    /// do {
    ///     try channel.sender.send(value)
    /// } catch .closed {
    ///     // Channel was closed
    /// }
    /// ```
    public struct Unbounded: ~Copyable, Sendable {
        @usableFromInline
        let storage: Storage

        /// View for sending elements to this channel.
        ///
        /// `Sender` is `Copyable` - multiple sender views can exist,
        /// and they all share the same underlying channel.
        /// Dropping a `Sender` has no lifecycle effect.
        public let sender: Sender

        /// View for receiving elements from this channel.
        ///
        /// `Receiver` is `~Copyable` - exactly one receiver exists per channel.
        /// This enforces single-receiver semantics at the type level.
        /// Dropping the `Receiver` has no lifecycle effect.
        public var receiver: Receiver

        /// Creates a new unbounded channel.
        public init() {
            let storage = Storage()
            self.storage = storage
            self.sender = Sender(storage: storage)
            self.receiver = Receiver(storage: storage)
        }
    }
}

extension Async.Channel.Unbounded where Element: ~Copyable {
    /// Consume the channel and return a `Take` for endpoint extraction.
    ///
    /// Use after extracting the sender (Copyable) to consume the channel
    /// and obtain both endpoints as a bundle:
    /// ```swift
    /// var channel = Async.Channel<Int>.Unbounded()
    /// let sender = channel.sender
    /// let ends = (consume channel).take().ends()
    /// ```
    public consuming func take() -> Take {
        Take(channel: consume self)
    }
}

extension Async.Channel.Unbounded where Element: ~Copyable {
    /// Close the channel, signaling no more elements will be sent.
    ///
    /// After close:
    /// - `send()` throws `.closed`
    /// - `receive()` drains buffer then returns `nil`
    public func close() {
        sender.close()
    }

    /// Whether the channel has been closed.
    public var closed: Bool {
        storage.withLock { $0.isClosed }
    }
}

#endif  // !hasFeature(Embedded)
