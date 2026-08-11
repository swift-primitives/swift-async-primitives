// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    extension Async.Channel.Typed.Rendezvous.Send where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// The ownership-preserving result of a rendezvous send.
        public enum Outcome: ~Copyable {
            /// The element was transferred exactly once to a receiver.
            case sent

            /// The element was not transferred and is returned to the caller.
            case rejected(Element, Async.Channel<Element>.Typed<Failure>.Error)
        }
    }

#endif  // !hasFeature(Embedded)
