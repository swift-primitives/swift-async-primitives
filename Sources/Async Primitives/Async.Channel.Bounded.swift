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
    /// Bounded channel with backpressure.
    ///
    /// Provides a capacity-limited channel where sends suspend when
    /// the buffer is full (backpressure) and receives suspend when empty.
    ///
    /// ## Usage
    /// ```swift
    /// let (sender, receiver) = Async.Channel<Int>.Bounded.create(capacity: 10)
    ///
    /// // Producer task (Sender is Copyable, Sendable)
    /// Task {
    ///     try await sender.send(1)
    ///     try await sender.send(2)
    ///     sender.close()
    /// }
    ///
    /// // Consumer (single task, Receiver enforces single-consumer)
    /// for try await value in receiver.elements {
    ///     print(value)
    /// }
    /// ```
    ///
    /// ## Design
    /// - `Sender`: Copyable, Sendable - can be shared across tasks
    /// - `Receiver`: Single-consumer (runtime precondition) - at most one
    ///   task may be suspended in `receive()` at a time
    /// - Auto-close: Channel closes when last Sender drops
    ///
    /// ## Error Handling
    /// Operations use typed throws for exhaustive error handling:
    /// ```swift
    /// do {
    ///     try await sender.send(value)
    /// } catch .closed {
    ///     // Channel was closed
    /// } catch .cancelled {
    ///     // Task was cancelled
    /// }
    /// ```
    public enum Bounded {
        /// Creates a bounded channel with separate sender and receiver handles.
        ///
        /// The returned `Sender` is Copyable and Sendable (can be shared across tasks),
        /// while `Receiver` enforces single-consumer semantics.
        ///
        /// The channel automatically closes when all `Sender` copies are dropped.
        ///
        /// - Parameter capacity: The maximum number of elements that can be buffered.
        ///   Must be greater than zero.
        /// - Returns: A tuple of `(Sender, Receiver)` handles.
        public static func create(capacity: Int) -> (Sender, Receiver) {
            precondition(capacity > 0, "Bounded channel capacity must be greater than zero")
            let storage = Storage(capacity: capacity)
            return (Sender(storage: storage), Receiver(storage: storage))
        }
    }
}
