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

// Async broadcast requires task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

public import Async_Primitives_Core

extension Async.Broadcast {
    /// Errors that can occur in broadcast operations.
    ///
    /// Aliased to ``Async/Lifecycle/Error``. `next()` throws `.cancelled`
    /// when the task is cancelled while waiting; the additional cases
    /// (`.shutdown`, `.timeout`) are reachable in principle but not
    /// produced by the current Broadcast surface.
    public typealias Error = Async.Lifecycle.Error
}

#endif  // !hasFeature(Embedded)
