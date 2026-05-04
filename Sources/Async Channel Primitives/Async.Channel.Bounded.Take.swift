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

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// Consuming accessor namespace.
        public struct Take: ~Copyable, Sendable {
            @usableFromInline
            var channel: Async.Channel<Element>.Bounded

            @usableFromInline
            init(channel: consuming Async.Channel<Element>.Bounded) {
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

#endif  // !hasFeature(Embedded)
