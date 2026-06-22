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

import Buffer_Primitives
public import Buffer_Arena_Primitive
public import Storage_Primitive

extension Async.Timer.Wheel {
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
    /// ## Usage
    ///
    /// ```swift
    /// let id = wheel.schedule(deadline: deadline)
    /// // ...later...
    /// let wasCancelled = wheel.cancel(id)
    /// ```
    public struct ID: Hashable, Sendable {
        /// The slot index in the wheel's storage arena.
        public let index: Int

        /// The generation counter for ABA prevention.
        public let generation: UInt32

        /// Creates an ID with the given index and generation.
        @inlinable
        public init(index: Int, generation: UInt32) {
            self.index = index
            self.generation = generation
        }
    }
}

// MARK: - Construction Helpers

extension Async.Timer.Wheel {
    /// Creates an ID from an arena position.
    ///
    /// This is the boundary where the arena's `Position` is widened
    /// to `ID` for external use.
    ///
    /// - Parameter position: The arena position handle.
    /// - Returns: A handle suitable for external use.
    @usableFromInline
    static func _makeID(
        position: Buffer<Storage_Primitive.Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<Async.Timer.Wheel<C>.Node>>.Arena.Position
    ) -> ID {
        ID(index: Int(position.index), generation: position.token)
    }

    /// Extracts the typed storage index from an ID.
    ///
    /// This is the boundary where the ID's `Int` index is narrowed
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
    ) -> Buffer<Storage_Primitive.Storage<Memory.Allocator<Memory.Heap>.Pool>.Generational<Async.Timer.Wheel<C>.Node>>.Arena.Position {
        .init(index: UInt32(id.index), token: id.generation)
    }
}
