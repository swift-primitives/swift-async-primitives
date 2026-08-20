// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    extension Async.Channel.Typed.Rendezvous
    where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// A bidirectional endpoint backed by two independent rendezvous directions.
        public struct Duplex: ~Copyable, Sendable {
            public let outbound: Sender
            public var inbound: Receiver

            @usableFromInline
            init(outbound: Sender, inbound: consuming Receiver) {
                self.outbound = outbound
                self.inbound = consume inbound
            }

            /// Creates a pair of zero-capacity duplex peers.
            public static func pair() -> (Self, Self) {
                var leftToRight = Async.Channel<Element>.Typed<Failure>.Rendezvous()
                var rightToLeft = Async.Channel<Element>.Typed<Failure>.Rendezvous()
                return (
                    Self(outbound: leftToRight.sender, inbound: consume rightToLeft.receiver),
                    Self(outbound: rightToLeft.sender, inbound: consume leftToRight.receiver)
                )
            }

            /// Terminates both directions successfully.
            public func shutdown() {
                outbound.finish()
                inbound.finish()
            }
        }
    }

#endif  // !hasFeature(Embedded)
