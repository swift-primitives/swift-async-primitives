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
    /// Namespace for timer-related primitives.
    ///
    /// Timer provides data structures for efficient time-based scheduling:
    /// - `Async.Timer.Wheel`: Hierarchical timer wheel with O(1) operations
    ///
    /// These primitives are callback-free, actor-owned building blocks.
    /// Higher-level async sleep and timeout APIs are composed at the IO layer.
    public enum Timer {}
}
