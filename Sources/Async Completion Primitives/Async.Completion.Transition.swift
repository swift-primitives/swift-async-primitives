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

extension Async.Completion {
    /// State transition namespace.
    public enum Transition {
        /// Error thrown when a state transition fails.
        public enum Error: Swift.Error, Sendable {
            /// The completion has already transitioned to a terminal state.
            case alreadyDone
        }
    }
}

#endif  // !hasFeature(Embedded)
