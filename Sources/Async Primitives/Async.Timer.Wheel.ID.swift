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
    /// Unique identifier for a scheduled timer.
    ///
    /// IDs are used to cancel timers before they fire. Each ID contains:
    /// - An index into the storage slab
    /// - A generation counter for ABA prevention
    ///
    /// ## Generation Safety
    ///
    /// When a timer fires or is cancelled, its storage slot is returned to
    /// the free list. If a new timer reuses that slot, it receives a new
    /// generation number. Attempts to cancel with an old ID (stale generation)
    /// will fail safely.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let id = wheel.schedule(deadline: deadline)
    /// // ...later...
    /// let wasCancelled = wheel.cancel(id)
    /// ```
    public struct ID: Sendable, Hashable {
        /// Index into the storage slab.
        @usableFromInline
        let index: UInt32

        /// Generation counter for ABA prevention.
        @usableFromInline
        let generation: UInt32

        /// Creates an ID with the given index and generation.
        @usableFromInline
        init(index: UInt32, generation: UInt32) {
            self.index = index
            self.generation = generation
        }
    }
}
