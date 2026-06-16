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

public import Async_Primitive
public import Async_Lifecycle_Primitives

extension Async.Semaphore {
    /// Errors thrown by semaphore operations.
    ///
    /// Aliased to ``Async/Lifecycle/Error`` (`shutdown` / `cancelled` /
    /// `timeout`). Precedence order: shutdown > cancelled > timeout.
    public typealias Error = Async.Lifecycle.Error
}
