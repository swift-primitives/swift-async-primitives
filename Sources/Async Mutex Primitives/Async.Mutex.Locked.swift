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

#if !hasFeature(Embedded) && canImport(Darwin)

extension Async.Mutex where Value: ~Copyable {
    /// A scoped view providing direct access to the mutex-protected value.
    ///
    /// `Locked` uses `nonmutating _modify` with interior mutability through
    /// a raw pointer. This enables mutation from a `let`-bound Mutex —
    /// the pointer doesn't change, only what it points to.
    ///
    /// The view is `~Copyable` to prevent escaping beyond the lock scope.
    ///
    /// Access the protected value through the `value` property:
    /// ```swift
    /// mutex.locked.value.count += 1
    /// mutex.locked.value.buffer.push(element, to: .back)
    /// ```
    @safe
    public struct Locked: ~Copyable {
        @usableFromInline
        let pointer: UnsafeMutablePointer<Value>

        @usableFromInline
        init(_ pointer: UnsafeMutablePointer<Value>) {
            unsafe (self.pointer = pointer)
        }
    }
}

// MARK: - Value Access

extension Async.Mutex.Locked where Value: ~Copyable {
    /// The mutex-protected value.
    ///
    /// Read access through `_read`, mutation through `nonmutating _modify`.
    /// Interior mutability: the pointer is immutable, mutation targets the pointee.
    @inlinable
    public var value: Value {
        _read { yield unsafe pointer.pointee }
        nonmutating _modify { yield unsafe &pointer.pointee }
    }
}

#endif
