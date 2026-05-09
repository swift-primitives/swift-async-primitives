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

// Ownership transfer extensions for Mutex with ~Copyable values.
//
// These extensions solve a fundamental ergonomic gap: Swift closures capture
// by reference, not by ownership transfer. Passing a `consuming ~Copyable`
// value into `Mutex.withLock` requires wrapping it in an Optional and using
// a multi-statement dance to move it inside the closure. These methods
// encapsulate that dance into a clean call-site API.
//
// See: swift-primitives/Experiments/bridge-noncopyable-ownership/ (2026-03-31)
// See: swift-institute/Research/noncopyable-ergonomics-compiler-state.md

#if !hasFeature(Embedded) && canImport(Synchronization)

    import Synchronization

    // MARK: - Consuming Value Transfer

    extension Async.Mutex where Value: ~Copyable {
        /// Lock the mutex with a value that the body must consume on every path.
        ///
        /// Transfers ownership of `value` into the locked closure. The body
        /// receives both the mutex-protected state and the value as `consuming`.
        /// Every code path in the body must consume the value — either by using
        /// it or by explicitly dropping it with `_ = consume value`.
        ///
        /// This eliminates the Optional slot dance required when passing
        /// `consuming ~Copyable` values through standard `withLock` closures.
        ///
        /// ## Example: Async.Bridge.push()
        ///
        /// ```swift
        /// // Before (4-statement dance):
        /// var slot: Element? = element
        /// mutex.withLock { state in
        ///     var tmp = slot; slot = nil
        ///     switch consume tmp {
        ///     case .some(let e): state.buffer.push(e, to: .back)
        ///     case .none: break
        ///     }
        /// }
        ///
        /// // After:
        /// mutex.withLock(consuming: element) { state, element in
        ///     state.buffer.push(consume element, to: .back)
        /// }
        /// ```
        ///
        /// - Parameters:
        ///   - value: The value to transfer into the locked scope.
        ///   - body: A closure receiving the mutex state and the value.
        ///           Must consume the value on every path.
        /// - Returns: The result of the body closure.
        @inlinable
        public func withLock<V: ~Copyable & Sendable, T: ~Copyable, E: Swift.Error>(
            consuming value: consuming sending V,
            body: (inout sending Value, consuming V) throws(E) -> sending T
        ) throws(E) -> sending T {
            var slot: V? = value
            return try withLock { (state: inout sending Value) throws(E) -> T in
                try body(&state, slot.take()!)
            }
        }
    }

    // MARK: - Deposit Value Transfer

    extension Async.Mutex where Value: ~Copyable {
        /// Lock the mutex with a deposited value that the body may or may not consume.
        ///
        /// Transfers ownership of `value` into the locked closure via an
        /// `inout Optional`. The body can consume the value with `.take()!`
        /// on some paths and leave it on others. Any unconsumed value is
        /// dropped when the method returns.
        ///
        /// Use this when different code paths have different ownership needs —
        /// for example, a channel send that buffers the element on the fast path
        /// but leaves it for the caller to handle on a suspend path.
        ///
        /// - Note: The caller cannot recover an unconsumed value. If the body
        ///   does not consume the value, it is dropped. For suspend-path retention,
        ///   the caller must own `var slot: Element?` directly and capture it
        ///   through standard `withLock`.
        ///
        /// - Parameters:
        ///   - value: The value to deposit into the locked scope.
        ///   - body: A closure receiving the mutex state and an inout Optional
        ///           containing the value. Use `.take()!` to consume.
        /// - Returns: The result of the body closure.
        @inlinable
        public func withLock<V: ~Copyable & Sendable, T: ~Copyable, E: Swift.Error>(
            deposit value: consuming sending V,
            body: (inout sending Value, inout V?) throws(E) -> sending T
        ) throws(E) -> sending T {
            var slot: V? = value
            return try withLock { (state: inout sending Value) throws(E) -> T in
                try body(&state, &slot)
            }
        }
    }

#endif  // !hasFeature(Embedded) && canImport(Synchronization)
