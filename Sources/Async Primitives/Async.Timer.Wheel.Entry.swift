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
    /// A timer entry yielded when a timer fires.
    ///
    /// Entry is yielded by `advance(to:yield:)` when a timer's deadline
    /// has been reached. It contains the timer's ID and original deadline.
    ///
    /// ## Exactly-Once Guarantee
    ///
    /// Each timer is yielded exactly once. The wheel removes the entry
    /// before yielding, and the entry cannot be duplicated (the wheel
    /// enforces this invariant internally).
    ///
    /// ## Usage
    ///
    /// The caller (typically a resumption funnel) uses the ID to look up
    /// the associated continuation and resume it:
    ///
    /// ```swift
    /// wheel.advance(to: now) { entry in
    ///     if let continuation = continuations.removeValue(forKey: entry.id) {
    ///         continuation.resume()
    ///     }
    /// }
    /// ```
    public struct Entry: Sendable, Hashable {
        /// The timer's unique identifier.
        public let id: ID

        /// The timer's original deadline.
        public let deadline: C.Instant

        /// Creates an entry with the given ID and deadline.
        @usableFromInline
        init(id: ID, deadline: C.Instant) {
            self.id = id
            self.deadline = deadline
        }
    }
}
