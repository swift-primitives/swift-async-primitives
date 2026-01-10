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
    /// Slab allocator for timer nodes.
    ///
    /// Storage provides O(1) allocation and deallocation of node slots
    /// using a free list. All memory is pre-allocated at initialization.
    ///
    /// ## Thread Safety
    ///
    /// Storage is marked `@unchecked Sendable` because it contains mutable
    /// state. Safety is guaranteed by the wheel's design: the wheel is
    /// `~Copyable` and intended for single-actor use. All mutations are
    /// serialized by the owning actor.
    ///
    /// ## Generation Counter
    ///
    /// Each allocation increments a global generation counter. When a slot
    /// is reused, the new node gets a new generation. This prevents the
    /// ABA problem where a stale ID might accidentally match a new timer.
    ///
    /// ## Free List
    ///
    /// The free list uses a parallel array (`freeLinks`) to store next-free
    /// indices. Sentinel value `UInt32.max` indicates end of list or
    /// exhausted state. This avoids Optional overhead.
    @usableFromInline
    struct Storage: ~Copyable, @unchecked Sendable {
        /// Node storage. Nil indicates a free slot.
        @usableFromInline
        var nodes: [Node?]
        
        /// Parallel array for free list linkage.
        /// `freeLinks[i]` is the next free index when `nodes[i]` is nil.
        /// Sentinel value `UInt32.max` indicates end of free list.
        @usableFromInline
        var freeLinks: [UInt32]
        
        /// Head of the free list. `UInt32.max` means exhausted.
        @usableFromInline
        var freeHead: UInt32
        
        /// Next generation counter for ABA prevention.
        @usableFromInline
        var generation: UInt32
        
        /// The storage capacity.
        @usableFromInline
        let capacity: Int
        
        /// Creates storage with the specified capacity.
        ///
        /// - Parameter capacity: Maximum number of concurrent timers.
        @usableFromInline
        init(capacity: Int) {
            self.capacity = capacity
            self.nodes = [Node?](repeating: nil, count: capacity)
            self.freeLinks = [UInt32](repeating: 0, count: capacity)
            self.generation = 0
            
            // Build free list: 0 → 1 → 2 → ... → (capacity-1) → sentinel
            if capacity > 0 {
                for i in 0..<(capacity - 1) {
                    freeLinks[i] = UInt32(i + 1)
                }
                freeLinks[capacity - 1] = UInt32.max // Sentinel for end
                freeHead = 0
            } else {
                freeHead = UInt32.max // Exhausted (empty capacity)
            }
        }
    }
}

// MARK: - Allocation

extension Async.Timer.Wheel.Storage {
    
    /// Allocates a slot from the free list.
    ///
    /// - Returns: A tuple of (index, generation), or nil if exhausted.
    ///
    /// - Complexity: O(1)
    @usableFromInline
    mutating func allocate() -> (index: UInt32, generation: UInt32)? {
        guard freeHead != UInt32.max else {
            return nil // Storage exhausted
        }
        
        let index = freeHead
        
        // Pop from free list
        let nextFree = freeLinks[Int(index)]
        freeHead = nextFree
        
        // Increment generation
        let gen = generation
        generation &+= 1
        
        return (index, gen)
    }
    
    /// Returns a slot to the free list.
    ///
    /// - Parameter index: The slot index to deallocate.
    ///
    /// - Complexity: O(1)
    /// - Precondition: The slot must be currently allocated.
    @usableFromInline
    mutating func deallocate(_ index: UInt32) {
        // Clear the node
        nodes[Int(index)] = nil
        
        // Push to free list
        freeLinks[Int(index)] = freeHead
        freeHead = index
    }
    
}

// MARK: - Access

extension Async.Timer.Wheel.Storage {
    
    /// Accesses the node at the given index.
    ///
    /// - Parameter index: The slot index.
    /// - Returns: The node, or nil if the slot is free.
    @usableFromInline
    subscript(_ index: UInt32) -> Async.Timer.Wheel<C>.Node? {
        get { nodes[Int(index)] }
        set { nodes[Int(index)] = newValue }
    }
    
    /// Removes and returns the node at the given index.
    ///
    /// This does NOT return the slot to the free list. Use `deallocate`
    /// separately if the slot should be freed.
    ///
    /// - Parameter index: The slot index.
    /// - Returns: The removed node, or nil if already empty.
    @usableFromInline
    mutating func take(_ index: UInt32) -> Async.Timer.Wheel<C>.Node? {
        let node = nodes[Int(index)]
        nodes[Int(index)] = nil
        return node
    }
    
}
