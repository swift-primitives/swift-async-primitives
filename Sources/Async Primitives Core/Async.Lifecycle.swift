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
    /// Namespace for lifecycle management primitives.
    ///
    /// Provides building blocks for implementing graceful shutdown:
    /// - `Lifecycle.State`: Three-state machine (open → closing → closed)
    ///
    /// This is a pure state machine with no built-in waiting or synchronization.
    /// Consumers embed `State` in their own synchronized state and call
    /// the mutating methods under their own lock.
    public enum Lifecycle {}
}
