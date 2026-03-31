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

extension Async.Lifecycle {
    /// Three-state lifecycle for graceful shutdown.
    ///
    /// ## States
    ///
    /// - `open`: Normal operation
    /// - `closing`: Draining existing work
    /// - `closed`: Fully shut down
    ///
    /// ## Thread Safety
    ///
    /// This is a pure value type with no built-in synchronization.
    /// Consumers must embed `State` in their own `Mutex`-protected state
    /// and call mutating methods while holding the lock.
    ///
    /// ## Usage Pattern
    ///
    /// ```swift
    /// struct MyResourceState {
    ///     var lifecycle: Async.Lifecycle.State = .open
    ///     var activeCount: Int = 0
    /// }
    ///
    /// let state = Mutex(MyResourceState())
    ///
    /// // Begin shutdown:
    /// let didBegin = state.withLock { $0.lifecycle.shutdown.begin() }
    ///
    /// // Complete shutdown when drained:
    /// state.withLock { state in
    ///     if state.activeCount == 0 {
    ///         state.lifecycle.shutdown.complete()
    ///     }
    /// }
    /// ```
    public enum State: Sendable, Equatable {
        /// Normal operation.
        case open

        /// Draining existing work.
        case closing

        /// Fully shut down.
        case closed
    }
}

// MARK: - State Queries

extension Async.Lifecycle.State {
    /// Whether the lifecycle is in the `open` state.
    @inlinable
    public var isOpen: Bool {
        self == .open
    }
}

// MARK: - Shutdown Accessor

extension Async.Lifecycle.State {
    @safe
    public struct Shutdown: ~Copyable, ~Escapable {
        @usableFromInline
        let pointer: UnsafeMutablePointer<Async.Lifecycle.State>

        @inlinable @_lifetime(borrow pointer)
        init(_ pointer: UnsafeMutablePointer<Async.Lifecycle.State>) {
            self.pointer = pointer
        }

        /// Whether shutdown is in progress (`closing` or `closed`).
        @inlinable
        public var isActive: Bool { unsafe pointer.pointee != .open }

        /// Whether shutdown is complete (`closed`).
        @inlinable
        public var isComplete: Bool { unsafe pointer.pointee == .closed }

        /// Transitions from `open` to `closing`.
        @discardableResult
        @inlinable
        public func begin() -> Bool {
            guard unsafe pointer.pointee == .open else { return false }
            unsafe pointer.pointee = .closing
            return true
        }

        /// Transitions from `closing` to `closed`.
        @discardableResult
        @inlinable
        public func complete() -> Bool {
            guard unsafe pointer.pointee == .closing else { return false }
            unsafe pointer.pointee = .closed
            return true
        }
    }

    /// Shutdown operations accessor.
    public var shutdown: Shutdown {
        mutating _read {
            yield unsafe Shutdown(&self)
        }
        mutating _modify {
            var view = unsafe Shutdown(&self)
            yield &view
        }
    }
}
