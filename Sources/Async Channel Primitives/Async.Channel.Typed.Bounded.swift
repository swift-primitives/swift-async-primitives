// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    public import Index_Primitives

    extension Async.Channel.Typed where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// A bounded typed channel that preserves the base channel's capacity,
        /// backpressure, cancellation, FIFO, and buffered-drain behavior.
        public struct Bounded: ~Copyable, Sendable {
            @usableFromInline let terminals: TerminalStorage

            /// The directional sending endpoint.
            public let sender: Sender

            /// The directional receiving endpoint.
            public var receiver: Receiver

            /// Creates a bounded channel with the supplied capacity.
            public init(capacity: Index<Element>.Count) {
                var raw = Async.Channel<Element>.Bounded(capacity: capacity)
                let terminals = TerminalStorage()
                self.terminals = terminals
                self.sender = Sender(raw: raw.sender, terminals: terminals)
                self.receiver = Receiver(
                    raw: consume raw.receiver,
                    closer: raw.sender,
                    terminals: terminals
                )
            }
        }
    }

#endif  // !hasFeature(Embedded)
