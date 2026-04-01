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

extension Async.Timer.Wheel {
    /// Bundles the deadline instant with its tick representation.
    @usableFromInline
    struct Deadline: Sendable {
        /// The original deadline instant (for yielding in Entry).
        @usableFromInline
        var instant: C.Instant

        /// The deadline as a tick number (for internal calculations).
        @usableFromInline
        var tick: Async.Timer.Wheel<C>.Tick

        @usableFromInline
        init(instant: C.Instant, tick: Async.Timer.Wheel<C>.Tick) {
            self.instant = instant
            self.tick = tick
        }
    }
}
