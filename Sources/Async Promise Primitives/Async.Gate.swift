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

// MARK: - Gate (Promise<Void> specialization)

extension Async {
    /// A one-shot synchronization primitive for async coordination.
    ///
    /// Gate is a `Promise<Void>` specialized for signaling without a value.
    /// Use when you need to signal "ready" or "done" without transferring data.
    ///
    /// ## Usage
    /// ```swift
    /// let ready = Async.Gate()
    ///
    /// // Waiter (async, non-embedded only)
    /// await ready.wait()
    ///
    /// // Waiter (callback, works everywhere)
    /// ready.wait { }
    ///
    /// // Signaler
    /// ready.open()
    /// ```
    public typealias Gate = Promise<Void>
}

extension Async.Promise where Value == Void {
    /// Opens the gate, releasing all waiting tasks.
    ///
    /// Equivalent to `fulfill(())`.
    ///
    /// - Returns: `true` if the gate was opened, `false` if already open.
    @discardableResult
    public func open() -> Bool {
        fulfill(())
    }

    /// Waits until the gate is opened (callback-based).
    ///
    /// If the gate is already open, the callback is invoked immediately.
    /// Otherwise, the callback is stored and invoked when `open()` is called.
    ///
    /// This method works on all platforms including embedded Swift.
    ///
    /// - Parameter callback: The callback to invoke when the gate opens.
    public func wait(_ callback: @escaping @Sendable () -> Void) {
        (self as Async.Promise<Void>).wait { _ in callback() }
    }

    /// Whether the gate is currently open.
    ///
    /// Equivalent to `isFulfilled`.
    public var isOpen: Bool {
        isFulfilled
    }
}

// MARK: - Async Gate Wait (Non-Embedded Only)

#if !hasFeature(Embedded)
    extension Async.Promise where Value == Void {
        /// Waits until the gate is opened (async).
        ///
        /// Equivalent to `await value()`.
        ///
        /// - Note: This method is only available on non-embedded platforms.
        ///   On embedded, use `wait(_:)` instead.
        nonisolated(nonsending)
            public func wait() async
        {
            _ = await value()
        }
    }
#endif
