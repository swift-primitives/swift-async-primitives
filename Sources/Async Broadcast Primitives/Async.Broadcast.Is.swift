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

extension Async.Broadcast {
    /// Lifecycle flags namespace (§2.2 compliant).
    struct Is {
        var finished: Bool = false
    }
}

#endif  // !hasFeature(Embedded)
