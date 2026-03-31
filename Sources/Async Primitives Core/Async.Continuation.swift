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

extension Async {
    #if !hasFeature(Embedded)
    /// Unified continuation that wraps either a `CheckedContinuation` or a callback.
    ///
    /// This provides a unified continuation API that works across embedded
    /// and non-embedded Swift. On non-embedded platforms, it can wrap either
    /// a `CheckedContinuation` (for async/await) or a callback (for callback-based APIs).
    /// On embedded platforms, it only uses callbacks.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Non-embedded: wrap a CheckedContinuation
    /// await withCheckedContinuation { (cont: CheckedContinuation<Int, Never>) in
    ///     let asyncCont = Async.Continuation(cont)
    ///     asyncCont.resume(returning: 42)
    /// }
    ///
    /// // Both platforms: wrap a callback
    /// let cont = Async.Continuation<Int> { value in
    ///     print("Got: \(value)")
    /// }
    /// cont.resume(returning: 42)
    /// ```
    public struct Continuation<T: Sendable>: Sendable {
        @usableFromInline
        let storage: Storage

        /// Creates a continuation wrapping a `CheckedContinuation`.
        @inlinable
        public init(_ continuation: CheckedContinuation<T, Never>) {
            self.storage = .checkedContinuation(continuation)
        }
    }
    #else
    /// Callback-based continuation for embedded platforms.
    ///
    /// This provides a unified continuation API that works across embedded
    /// and non-embedded Swift. On embedded platforms, it uses a callback
    /// since `CheckedContinuation` is unavailable.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Embedded: create with a callback
    /// let cont = Async.Continuation<Int> { value in
    ///     print("Got: \(value)")
    /// }
    /// cont.resume(returning: 42)
    /// ```
    public struct Continuation<T: Sendable>: Sendable {
        @usableFromInline
        let callback: @Sendable (sending T) -> Void

        /// Creates a continuation with a callback.
        @inlinable
        public init(_ callback: @escaping @Sendable (sending T) -> Void) {
            self.callback = callback
        }
    }
    #endif
}

#if !hasFeature(Embedded)
extension Async.Continuation {
    /// Creates a continuation with a callback.
    @inlinable
    public init(_ callback: @escaping @Sendable (sending T) -> Void) {
        self.storage = .callback(callback)
    }

    /// Resumes the continuation with a value.
    @inlinable
    public func resume(returning value: consuming T) {
        switch storage {
        case .checkedContinuation(let continuation):
            continuation.resume(returning: value)
        case .callback(let callback):
            callback(value)
        }
    }
}
#else
extension Async.Continuation {
    /// Resumes the continuation with a value.
    @inlinable
    public func resume(returning value: consuming T) {
        callback(value)
    }
}
#endif
