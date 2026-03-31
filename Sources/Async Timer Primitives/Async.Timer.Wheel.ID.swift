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
    public enum _Entry {}

    /// Unique identifier for a scheduled timer.
    ///
    /// IDs are used to cancel timers before they fire. Each ID contains:
    /// - An index into the storage arena
    /// - A generation token for ABA prevention
    ///
    /// ## Generation Safety
    ///
    /// When a timer fires or is cancelled, its storage slot is returned to
    /// the free list. If a new timer reuses that slot, the slot's per-slot
    /// generation token increments. Attempts to cancel with an old ID
    /// (stale token) will fail safely.
    ///
    /// ## Implementation Note
    ///
    /// `ID` is implemented as `Handle<_Entry>` to unify handle
    /// types across the Swift Institute primitives. Internally, the wheel
    /// bridges between `Handle` and `Buffer.Arena.Position`.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let id = wheel.schedule(deadline: deadline)
    /// // ...later...
    /// let wasCancelled = wheel.cancel(id)
    /// ```
    public typealias ID = Handle<_Entry>
}

// MARK: - Construction Helpers

extension Async.Timer.Wheel {
    /// Creates an ID from an arena position.
    ///
    /// This is the boundary where the arena's `Position` is widened
    /// to `Handle<_Entry>` for external use.
    ///
    /// - Parameter position: The arena position handle.
    /// - Returns: A handle suitable for external use.
    @usableFromInline
    static func _makeID(
        position: Buffer<Async.Timer.Wheel<C>.Node>.Arena.Position
    ) -> ID {
        ID(index: Int(position.index), generation: position.token)
    }

    /// Extracts the typed storage index from an ID.
    ///
    /// This is the boundary where the `Handle`'s `Int` index is narrowed
    /// back to the typed `Index<Node>` for arena access.
    ///
    /// - Parameter id: The timer ID.
    /// - Returns: The typed slot index.
    @usableFromInline
    static func _storageIndex(_ id: ID) -> Index<Async.Timer.Wheel<C>.Node> {
        Index<Node>(Ordinal(UInt(id.index)))
    }

    /// Reconstructs an arena position from an ID.
    ///
    /// Used for position-based validation (e.g., `storage.isValid`).
    ///
    /// - Parameter id: The timer ID.
    /// - Returns: The arena position handle.
    @usableFromInline
    static func _position(
        _ id: ID
    ) -> Buffer<Async.Timer.Wheel<C>.Node>.Arena.Position {
        .init(index: UInt32(id.index), token: id.generation)
    }
}
