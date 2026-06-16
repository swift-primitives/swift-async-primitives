// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025-2026 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

internal import Async_Mutex_Primitives
public import Async_Primitive
public import Async_Promise_Primitives

extension Async {
    /// A task-suspending counting semaphore for async admission control.
    ///
    /// Semaphore limits concurrent access to a resource or region to at most
    /// `capacity` tasks. Tasks that exceed the limit suspend in FIFO order
    /// until a permit becomes available.
    ///
    /// ## Core Operations
    ///
    /// - `wait()`: Acquires a permit, suspending if none available.
    /// - `signal()`: Releases a permit, resuming the next waiter if any.
    /// - `withPermit { }`: Scoped acquire + release.
    ///
    /// ## Cancellation and Timeout
    ///
    /// - `wait()` respects Task cancellation: throws `.cancelled`.
    /// - `wait(timeout:)` suspends up to a Duration: throws `.timeout`.
    ///
    /// ## Shutdown
    ///
    /// - `shutdown()` wakes all waiters with `.shutdown` error.
    /// - Future waits after shutdown throw `.shutdown` immediately.
    ///
    /// ## Thread Safety
    ///
    /// All operations are protected by an internal mutex. The type is
    /// `Sendable` and safe to share across isolation domains.
    public final class Semaphore: Sendable {
        @usableFromInline
        let _state: Async.Mutex<State>

        /// Shutdown notification gate.
        @usableFromInline
        let _shutdownGate: Async.Gate

        /// Creates a counting semaphore with the given capacity.
        ///
        /// - Parameter capacity: Maximum number of concurrent permits.
        /// - Precondition: `capacity` must be at least 1.
        public init(capacity: Int) {
            precondition(capacity >= 1, "Semaphore requires capacity >= 1")
            self._state = Async.Mutex(State(capacity: capacity))
            self._shutdownGate = Async.Gate()
        }
    }
}
