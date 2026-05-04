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
        /// A value-owning mutex providing closure-based access to ~Copyable state.
        ///
        /// Uses `os_unfair_lock` for mutual exclusion. All mutation flows through
        /// `withLock(_:)` / `withLockIfAvailable(_:)`, which receive the protected
        /// value as `inout sending Value`.
        ///
        /// Storage is `let`-bound with interior mutability through raw pointers,
        /// so Mutex works correctly with `let` bindings on classes.
        ///
        /// ## Fairness
        ///
        /// `os_unfair_lock` is **unfair by default**. Contended waiters are not
        /// guaranteed to acquire in FIFO order, and a heavily-contending task can
        /// starve others. For ordered/fair admission, compose `Async.Semaphore`
        /// (FIFO) on top of the protected state rather than using `Mutex` directly.
        ///
        /// ## Usage
        ///
        /// ```swift
        /// let mutex = Async.Mutex(State())
        /// mutex.withLock { state in state.count += 1 }
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
