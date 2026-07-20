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

// Async broadcast requires task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

    extension Async.Broadcast {
        /// Observable signal fired when a lagging subscriber's cursor is
        /// advanced past replay-buffer entries dropped by capacity trimming.
        ///
        /// `Async.Broadcast` bounds its replay buffer to `bufferLimit`
        /// (see `send(_:)`); a subscriber that falls behind the resulting
        /// floor has its cursor advanced past the dropped entries so it
        /// keeps making progress instead of pinning the buffer forever
        /// (F-002 / `3e27e44`). Prior to this signal that advance was
        /// silent: the subscriber's next `next()` simply resumed at the
        /// oldest survivor with no indication a gap occurred. `Loss` makes
        /// that sacrifice observable, mirroring the ecosystem's own
        /// `Cache.Evict` effect shape (a typed, reason-carrying value
        /// decoupled from the type's primary read path) rather than
        /// widening `next()`'s outcome surface — see
        /// `Research/broadcast-bounded-replay-semantics.md`, option (e2).
        ///
        /// ## When this fires
        /// - Fires once per subscriber whose cursor is behind the floor
        ///   established by a `send(_:)` that actually trims the buffer —
        ///   i.e. exactly at the site in `send(_:)` where that
        ///   subscriber's `cursor` is reassigned past the dropped entries.
        /// - Does **not** fire for a subscriber consuming in step with
        ///   `send(_:)` (nothing was dropped past its cursor).
        /// - Does **not** fire for a subscriber that calls `subscribe()`
        ///   after a drop already happened: a new subscription's cursor
        ///   starts at the current `next.index`, which is always at or
        ///   ahead of any previously-established floor, so replaying the
        ///   surviving window is never mistaken for loss.
        /// - Does **not** fire at all unless a handler is registered via
        ///   `init(bufferCapacity:onLoss:)` — registration is additive and
        ///   defaults to `nil`, so existing `Broadcast` consumers observe
        ///   no behavior change.
        ///
        /// ## Threading / isolation
        /// - The registered handler is invoked synchronously, inline, on
        ///   whatever isolation context called `send(_:)`. It is never
        ///   dispatched onto a `Task` and never suspends `send(_:)` —
        ///   `send(_:)`'s "synchronous, never blocks" contract is
        ///   unchanged.
        /// - The handler is invoked strictly after `Broadcast`'s internal
        ///   lock has been released for that `send(_:)` call (the same
        ///   discipline `send(_:)` already uses to resume waiting
        ///   continuations outside the lock), so a handler that calls
        ///   back into the same `Broadcast` (e.g. `subscribe()`,
        ///   `send(_:)`, iterating a subscription) cannot deadlock against
        ///   it and cannot observe an inconsistent snapshot of state.
        /// - The handler closure is `@Sendable`: `Broadcast` is `Sendable`
        ///   and `send(_:)` may be invoked from any isolation domain, so
        ///   the handler must tolerate being called from any of them.
        public struct Loss: Sendable {
            /// The identifier of the subscriber whose cursor was advanced.
            ///
            /// Stable for the lifetime of the subscription (assigned once
            /// by `subscribe()`); not exposed elsewhere on the public
            /// `Subscription` surface today, but usable to correlate
            /// repeated loss events for the same lagging subscriber across
            /// multiple `send(_:)` calls.
            public let subscriberID: UInt64

            /// The number of buffered entries this subscriber's cursor
            /// skipped over.
            ///
            /// Always positive: this signal only fires when the
            /// subscriber's prior cursor was strictly behind the new
            /// floor.
            public let droppedCount: Int

            /// The index the subscriber's cursor was advanced to — the
            /// index of the oldest entry still present in the replay
            /// buffer after this drop.
            public let resumingAtIndex: UInt64

            /// Why the loss occurred.
            public let reason: Reason

            /// Creates a loss signal.
            ///
            /// - Parameters:
            ///   - subscriberID: The subscriber whose cursor was advanced.
            ///   - droppedCount: The number of entries skipped over.
            ///   - resumingAtIndex: The index the cursor was advanced to.
            ///   - reason: Why the loss occurred.
            @inlinable
            public init(subscriberID: UInt64, droppedCount: Int, resumingAtIndex: UInt64, reason: Reason) {
                self.subscriberID = subscriberID
                self.droppedCount = droppedCount
                self.resumingAtIndex = resumingAtIndex
                self.reason = reason
            }
        }

    }

    extension Async.Broadcast.Loss {
        /// The reason a subscriber's cursor was advanced past dropped
        /// entries.
        ///
        /// Mirrors `Cache.Evict.Reason`'s shape: a `Sendable`, `Equatable`
        /// cause enum kept open to additional, additively-named cases
        /// rather than collapsed to a `Bool`. `Async.Broadcast` currently
        /// has exactly one drop cause (unconditional capacity trimming —
        /// see F-002 / `3e27e44`).
        public enum Reason: Sendable, Equatable {
            /// The replay buffer was trimmed to `bufferLimit` and this
            /// subscriber's cursor had fallen behind the resulting floor.
            case capacityLimit
        }
    }

#endif  // !hasFeature(Embedded)
