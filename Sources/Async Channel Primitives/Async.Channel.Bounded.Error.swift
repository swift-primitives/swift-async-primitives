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

// Async channels require task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// Errors that can occur during bounded channel operations.
        public typealias Error = Async.Channel<Element>.Error
    }

#endif  // !hasFeature(Embedded)
