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

import Synchronization

extension Async {
    /// Namespace for waiter queue primitives.
    ///
    /// Provides building blocks for implementing waiting patterns:
    /// - `Waiter.Flag`: Atomic flags for cancellation/timeout signaling
    /// - `Waiter.Resumption`: Deferred resumption thunk
    /// - `Waiter.Queue`: FIFO queue with flag-aware dequeue
    ///
    /// These primitives enforce the deferred resumption pattern:
    /// continuations are NEVER resumed while holding a lock.
    public enum Waiter {}
}
