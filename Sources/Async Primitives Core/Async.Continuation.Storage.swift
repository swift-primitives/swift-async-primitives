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

#if !hasFeature(Embedded)
    extension Async.Continuation {
        @usableFromInline
        enum Storage: Sendable {
            case checkedContinuation(CheckedContinuation<T, Never>)
            case callback(@Sendable (sending T) -> Void)
        }
    }
#endif
