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
        // SAFETY: Encapsulates unsafe internals behind a safe API; see
        // SAFETY: [MEM-SAFE-024] for the absorber-pattern taxonomy.
        //
        // `~Copyable` mirrors Swift 6.4's `Continuation` (SE-0528, "Noncopyable
        // continuation"): a continuation is a single-use resource, so the type
        // prevents accidental copies and `resume` consumes it. On the current 6.3.3
        // build toolchain the stdlib `Continuation` is unavailable (`@available(6.4)`
        // + `$BuiltinContinuationNonCopyableSuccess`), so this wraps the still-Copyable
        // `UnsafeContinuation` internally while presenting the 6.4-aligned surface.
        // Unlike the checked `Continuation`, the `Unsafe` variant carries no deinit
        // trap — the caller guarantees exactly-once resumption.
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
        public struct Unsafe: ~Copyable, @unchecked Sendable {
            @usableFromInline
            let _base: UnsafeContinuation<T, Never>

            /// Wraps a raw `UnsafeContinuation`, concentrating its unsafety at this single init site.
            @inlinable
            public init(_ base: UnsafeContinuation<T, Never>) {
                unsafe (self._base = base)
            }
        }
    }

    extension Async.Continuation.Unsafe {
        /// Resumes the wrapped continuation exactly once, consuming this wrapper.
        ///
        /// - Parameter value: The value to resume the continuation with.
        @inlinable
        public consuming func resume(returning value: consuming sending T) {
            unsafe _base.resume(returning: value)
        }
    }

#endif  // !hasFeature(Embedded)
