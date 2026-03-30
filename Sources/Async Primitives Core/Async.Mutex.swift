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

#if !hasFeature(Embedded) && canImport(Synchronization)
@_exported public import Synchronization

extension Async {
    /// A value-owning mutex for thread synchronization.
    ///
    /// Uses `Synchronization.Mutex` from the Swift standard library.
    public typealias Mutex = Synchronization.Mutex
}

#elseif !hasFeature(Embedded) && canImport(Kernel_Primitives)
@_exported public import Kernel_Primitives

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

        @inlinable
        public func withLock<T, E: Error>(_ body: (inout Value) throws(E) -> T) throws(E) -> T {
            try body(&_value)
        }

        @inlinable
        public func withLockIfAvailable<T, E: Error>(_ body: (inout Value) throws(E) -> T) throws(E) -> T? {
            try body(&_value)
        }
    }
}

#endif
