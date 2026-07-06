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

// MARK: - Shutdown Type

extension Async.Lifecycle.State {
    // SAFETY: Encapsulates unsafe internals behind a safe API; see
    // SAFETY: [MEM-SAFE-024] for the absorber-pattern taxonomy.
    /// A borrowed view over lifecycle state exposing shutdown transition operations.
    @safe
    public struct Shutdown: ~Copyable, ~Escapable {
        @usableFromInline
        let pointer: UnsafeMutablePointer<Async.Lifecycle.State>

        @inlinable @_lifetime(borrow pointer)
        init(_ pointer: UnsafeMutablePointer<Async.Lifecycle.State>) {
            unsafe self.pointer = pointer
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

// MARK: - Shutdown Operations

extension Async.Lifecycle.State.Shutdown {
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
