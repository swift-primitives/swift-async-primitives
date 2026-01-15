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

import Async_Primitives
import Testing

@Suite
struct AsyncTests {

    @Test
    func `Async namespace exists`() {
        _ = Async.self
        _ = Async.Channel<Never>.self
    }
}
