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

#if !hasFeature(Embedded)

extension Async.Continuation {
    /// Safe wrapper around `UnsafeContinuation` for performance-critical paths.
    ///
    /// Where ``Async/Continuation`` wraps `CheckedContinuation` (with runtime
    /// checking), `Unsafe` wraps `UnsafeContinuation` (no checking overhead).
    ///
    /// ## Safety
    ///
    /// The caller must ensure each continuation is resumed exactly once.
    /// Channel state machines enforce this invariant structurally.
    ///
    /// ## Purpose
    ///
    /// `UnsafeContinuation` is `@unsafe` in the Swift standard library. Under
    /// `StrictMemorySafety`, every expression that touches one — storing,
    /// passing, pattern-matching — emits a warning. This wrapper concentrates
    /// the unsafety into two sites (init + resume) instead of propagating it
    /// to every consumer.
    @safe
    public struct Unsafe: Sendable {
        @usableFromInline
        let _base: UnsafeContinuation<T, Never>

        @inlinable
        public init(_ base: UnsafeContinuation<T, Never>) {
            unsafe (self._base = base)
        }

        @inlinable
        public func resume(returning value: consuming T) {
            unsafe _base.resume(returning: value)
        }
    }
}

#endif  // !hasFeature(Embedded)
