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
public import Darwin.os.lock

// MARK: - Mutex

extension Async {
    /// A value-owning mutex providing both closure-based and coroutine-based access.
    ///
    /// Uses `os_unfair_lock` for mutual exclusion. Provides two access patterns:
    /// - `withLock(_:)`: Closure-based, suitable for transactional operations.
    /// - `locked`: Coroutine-based (`_read`), enabling direct property access
    ///   without closures, Optional wrappers, or `.take()!` for ~Copyable values.
    ///
    /// All properties are `let`-bound with interior mutability through raw pointers.
    /// The `locked` accessor uses `_read` with `nonmutating _modify` on the view,
    /// so Mutex works correctly with `let` bindings on classes.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let mutex = Async.Mutex(State())
    ///
    /// // Closure API (transactional — multiple state reads/writes under one lock)
    /// mutex.withLock { state in state.count += 1 }
    ///
    /// // Coroutine API (direct access — single lock per access)
    /// mutex.locked.value.count += 1
    /// ```
    public struct Mutex<Value: ~Copyable>: ~Copyable {
        // MARK: - Raw Storage

        @safe
        @_rawLayout(like: Value, movesAsLike)
        @usableFromInline
        struct _Value: ~Copyable {
            @inlinable init() {}
        }

        @safe
        @_rawLayout(like: os_unfair_lock_s)
        @usableFromInline
        struct _Lock: ~Copyable, @unchecked Sendable {
            @inlinable init() {}
        }

        @usableFromInline
        let _lockRaw: _Lock

        @usableFromInline
        let _valueRaw: _Value

        @inlinable
        public init(_ value: consuming sending Value) {
            _lockRaw = _Lock()
            _valueRaw = _Value()
            unsafe _lockPointer().initialize(to: os_unfair_lock_s())
            unsafe _valuePointer().initialize(to: value)
        }
    }
}

/// ## Safety Invariant
/// Internal `os_unfair_lock` serializes all access to the stored value.
extension Async.Mutex: @unchecked Sendable where Value: ~Copyable {}
/// Access serialized by external lock.
extension Async.Mutex._Value: @unchecked Sendable where Value: ~Copyable {}

// MARK: - Lock Internals

extension Async.Mutex where Value: ~Copyable {
    @usableFromInline
    func _lockPointer() -> UnsafeMutablePointer<os_unfair_lock_s> {
        unsafe withUnsafePointer(to: _lockRaw) { base in
            unsafe UnsafeMutablePointer(
                mutating: UnsafeRawPointer(base)
                    .assumingMemoryBound(to: os_unfair_lock_s.self)
            )
        }
    }

    @usableFromInline
    func _valuePointer() -> UnsafeMutablePointer<Value> {
        unsafe withUnsafePointer(to: _valueRaw) { base in
            unsafe UnsafeMutablePointer(
                mutating: UnsafeRawPointer(base)
                    .assumingMemoryBound(to: Value.self)
            )
        }
    }

    @usableFromInline
    func _lock() { unsafe os_unfair_lock_lock(_lockPointer()) }

    @usableFromInline
    func _unlock() { unsafe os_unfair_lock_unlock(_lockPointer()) }
}

// MARK: - Closure API

extension Async.Mutex where Value: ~Copyable {
    /// Acquires the lock and invokes `body` with the protected value.
    ///
    /// - Parameter body: A closure receiving exclusive access to the value.
    /// - Returns: The result of the body closure.
    @inlinable
    public borrowing func withLock<T: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending T
    ) throws(E) -> sending T {
        _lock()
        defer { _unlock() }
        return try unsafe body(&_valuePointer().pointee)
    }

    /// Attempts to acquire the lock without blocking.
    ///
    /// - Parameter body: A closure receiving exclusive access to the value.
    /// - Returns: The result of the body closure, or `nil` if the lock is held.
    @inlinable
    public borrowing func withLockIfAvailable<T: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending T
    ) throws(E) -> sending T? {
        guard unsafe os_unfair_lock_trylock(_lockPointer()) else { return nil }
        defer { _unlock() }
        return try unsafe body(&_valuePointer().pointee)
    }
}

// MARK: - Coroutine API

extension Async.Mutex where Value: ~Copyable {
    /// A locked view providing direct property access to the protected value.
    ///
    /// The lock is held for the duration of the `_read` coroutine scope.
    /// Each access to `locked` acquires and releases the lock independently.
    ///
    /// For transactional operations requiring multiple state reads/writes
    /// under a single lock acquisition, use `withLock(_:)` instead.
    ///
    /// ```swift
    /// mutex.locked.value.count += 1
    /// ```
    @inlinable
    public var locked: Locked {
        _read {
            _lock()
            defer { _unlock() }
            yield unsafe Locked(_valuePointer())
        }
    }
}

#elseif !hasFeature(Embedded) && canImport(Synchronization)
@_exported public import Synchronization

extension Async {
    /// A value-owning mutex for thread synchronization.
    ///
    /// Uses `Synchronization.Mutex` from the Swift standard library.
    public typealias Mutex = Synchronization.Mutex
}

#elseif !hasFeature(Embedded) && canImport(Kernel_Thread_Primitives)
@_exported public import Kernel_Thread_Primitives

extension Async {
    /// A value-owning mutex for thread synchronization.
    ///
    /// Uses `Kernel.Thread.Mutex.Value` for platforms with a kernel
    /// but without the Synchronization module.
    public typealias Mutex = Kernel.Thread.Mutex.Value
}

#else

extension Async {
    /// A no-op mutex for single-threaded embedded environments.
    ///
    /// On embedded platforms there is no OS kernel and typically no threading.
    /// This provides API compatibility while compiling to no-ops.
    public final class Mutex<Value: ~Copyable>: @unchecked Sendable {
        @usableFromInline
        var _value: Value

        @inlinable
        public init(_ value: consuming sending Value) {
            self._value = value
        }
    }
}

extension Async.Mutex where Value: ~Copyable {
    @inlinable
    public func withLock<T: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending T
    ) throws(E) -> sending T {
        try body(&_value)
    }

    @inlinable
    public func withLockIfAvailable<T: ~Copyable, E: Error>(
        _ body: (inout sending Value) throws(E) -> sending T
    ) throws(E) -> sending T? {
        try body(&_value)
    }
}

#endif
