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

extension Async.Channel {
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
    public struct Unbounded: ~Copyable, @unchecked Sendable {
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
            storage.withLock { $0.closed }
        }
    }
}

// MARK: - Take (consuming accessors)

extension Async.Channel.Unbounded {
    /// Consuming accessor for moving endpoints out of the channel.
    ///
    /// ```swift
    /// let ends = channel.take().ends()
    /// try ends.sender.send(42)
    /// let value = try await ends.receiver.receive()
    /// ```
    public consuming func take() -> Take {
        Take(channel: consume self)
    }

    /// Consuming accessor namespace.
    public struct Take: ~Copyable, @unchecked Sendable {
        @usableFromInline
        var channel: Async.Channel<Element>.Unbounded

        @usableFromInline
        init(channel: consuming Async.Channel<Element>.Unbounded) {
            self.channel = channel
        }

        /// Consume the channel and return both endpoints as a bundle.
        public consuming func ends() -> Ends {
            let storage = channel.storage
            let receiver = consume channel.receiver
            return Ends(storage: storage, receiver: receiver)
        }
    }
}

// MARK: - Ends

extension Async.Channel.Unbounded {
    /// Bundle containing both sender and receiver.
    ///
    /// `Ends` is `~Copyable` because it contains the `~Copyable` receiver.
    /// Use `channel.take.ends` to consume the channel and obtain this bundle.
    public struct Ends: ~Copyable, @unchecked Sendable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        var _receiver: Receiver

        /// View for receiving elements.
        public var receiver: Receiver {
            _read {
                yield _receiver
            }
            _modify {
                yield &_receiver
            }
        }

        /// View for sending elements.
        public var sender: Sender {
            Sender(storage: storage)
        }

        @usableFromInline
        init(storage: Storage, receiver: consuming Receiver) {
            self.storage = storage
            self._receiver = receiver
        }

        /// Close the channel.
        public func close() {
            sender.close()
        }

        /// Whether the channel has been closed.
        public var closed: Bool {
            sender.closed
        }
    }
}
