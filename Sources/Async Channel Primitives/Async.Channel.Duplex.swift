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

#if !hasFeature(Embedded)

    public import Index_Primitives

    extension Async.Channel where Element: ~Copyable {
        /// A pairable, typed bidirectional channel endpoint.
        ///
        /// Each endpoint has an outbound sender and an inbound receiver. Closing
        /// outbound is a half-close: its peer drains that direction before seeing
        /// terminal state, while inbound remains available until the peer closes
        /// its own outbound direction. Failure crosses only the matching direction.
        public struct Duplex<Failure: Swift.Error & Sendable>: ~Copyable, Sendable {
            /// The direction carrying values from this endpoint to its peer.
            public let outbound: Typed<Failure>.Sender

            /// The direction carrying values from the peer to this endpoint.
            public var inbound: Typed<Failure>.Receiver

            @usableFromInline
            init(outbound: Typed<Failure>.Sender, inbound: consuming Typed<Failure>.Receiver) {
                self.outbound = outbound
                self.inbound = consume inbound
            }
        }
    }

    extension Async.Channel.Duplex where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// Creates two peers connected by independent typed bounded directions.
        ///
        /// Each direction has the supplied capacity. Terminal operations remain
        /// directional: callers finish or fail `outbound`, then continue draining
        /// `inbound` until the peer has independently terminated it.
        public static func pair(capacity: Index<Element>.Count) -> (Self, Self) {
            var leftToRight = Typed<Failure>.Bounded(capacity: capacity)
            var rightToLeft = Typed<Failure>.Bounded(capacity: capacity)

            return (
                Self(outbound: leftToRight.sender, inbound: consume rightToLeft.receiver),
                Self(outbound: rightToLeft.sender, inbound: consume leftToRight.receiver)
            )
        }

        /// Creates two peers connected by independent zero-capacity directions.
        public static func pair() -> (
            Async.Channel<Element>.Typed<Failure>.Rendezvous.Duplex,
            Async.Channel<Element>.Typed<Failure>.Rendezvous.Duplex
        ) {
            Async.Channel<Element>.Typed<Failure>.Rendezvous.Duplex.pair()
        }
    }

#endif  // !hasFeature(Embedded)
