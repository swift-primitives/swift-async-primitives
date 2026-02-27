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

public import Handle_Primitives

extension Async.Timer.Wheel {
    /// Phantom type tag for timer wheel handles.
    ///
    /// This type exists solely to distinguish `Async.Timer.Wheel.ID` handles
    /// from other handle types at compile time.
    public enum _TimerWheelEntryTag {}

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
    /// ## Implementation Note
    ///
    /// `ID` is implemented as `Handle<_TimerWheelEntryTag>` to unify handle
    /// types across the Swift Institute primitives. The wheel's validation
    /// semantics remain wheel-specific (global epoch, not per-slot generation).
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let id = wheel.schedule(deadline: deadline)
    /// // ...later...
    /// let wasCancelled = wheel.cancel(id)
    /// ```
    public typealias ID = Handle<_TimerWheelEntryTag>
}

// MARK: - Construction Helpers

extension Async.Timer.Wheel {
    /// Creates an ID from the storage allocation result.
    ///
    /// This is the boundary where the typed `Storage.Index` is widened
    /// to `Int` for the `Handle`'s `SlotAddress`.
    ///
    /// - Parameters:
    ///   - index: The typed storage index.
    ///   - generation: The generation counter.
    /// - Returns: A handle suitable for external use.
    @usableFromInline
    static func _makeID(index: Storage.Index, generation: UInt32) -> ID {
        ID(index: Int(index.rawValue), generation: generation)
    }

    /// Extracts the storage index from an ID.
    ///
    /// This is the boundary where the `Handle`'s `Int` index is narrowed
    /// back to the typed `Storage.Index`.
    ///
    /// - Parameter id: The timer ID.
    /// - Returns: The typed storage index.
    @usableFromInline
    static func _storageIndex(_ id: ID) -> Storage.Index {
        Storage.Index(__unchecked: (), UInt32(id.index))
    }
}
