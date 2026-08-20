// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    public import Async_Waiter_Primitives
    public import Ownership_Primitives
    public import Column_Primitives
    public import Deque_Primitives

    extension Async.Channel.Typed where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// A typed zero-capacity channel that pairs senders and receivers directly.
        ///
        /// The channel stores FIFO waiter references but never stores an element in
        /// channel state. An element remains in its sender-owned slot until a
        /// receiver takes it exactly once. Cancellation or terminal rejection
        /// returns an unpaired element through ``Send/Outcome/rejected(_:_:)``.
        public struct Rendezvous: ~Copyable, Sendable {
            @usableFromInline let storage: Storage

            /// The directional sending endpoint.
            public let sender: Sender

            /// The directional receiving endpoint.
            public var receiver: Receiver

            /// Creates a zero-capacity typed rendezvous channel.
            public init() {
                let storage = Storage()
                self.storage = storage
                self.sender = Sender(storage: storage)
                self.receiver = Receiver(storage: storage)
            }
        }
    }

#endif  // !hasFeature(Embedded)
