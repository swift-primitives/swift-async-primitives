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

// Async channels require task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

public import Ownership_Primitives
public import Synchronization

extension Async.Channel.Bounded where Element: ~Copyable {
    /// Thread-safe storage wrapping the state machine.
    ///
    /// Uses `Ownership.Mutable.Unchecked` to give the channel reference semantics
    /// while keeping a struct interface. Thread safety is provided by the
    /// wrapped `Mutex`.
    @usableFromInline
    struct Storage: Sendable {
        @usableFromInline
        let _storage: Ownership.Mutable<Mutex<State>>.Unchecked

        /// Slot for transferring ~Copyable elements outside the continuation.
        /// The continuation carries a lightweight Signal; the element travels here.
        @usableFromInline
        let deliverySlot: Ownership.Slot<Element>

        @usableFromInline
        init(capacity: Index<Element>.Count) {
            self._storage = Ownership.Mutable.Unchecked(Mutex(State(capacity: capacity)))
            self.deliverySlot = Ownership.Slot()
        }

        @inlinable
        func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout State) throws(E) -> sending T) throws(E) -> sending T {
            try _storage.mutable.value.withLock { (state: inout State) throws(E) -> T in
                try body(&state)
            }
        }

        @inlinable
        func withLockAndElement<T: ~Copyable, E: Swift.Error>(
            _ element: inout Element?,
            _ body: (inout State, inout Element?) throws(E) -> sending T
        ) throws(E) -> sending T {
            try _storage.mutable.value.withLock { (state: inout State) throws(E) -> T in
                try body(&state, &element)
            }
        }
    }
}

#endif  // !hasFeature(Embedded)
