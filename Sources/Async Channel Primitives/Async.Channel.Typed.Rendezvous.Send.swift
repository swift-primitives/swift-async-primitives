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
        /// Namespace for ownership-preserving send results.
        public enum Send {}
    }

#endif  // !hasFeature(Embedded)
