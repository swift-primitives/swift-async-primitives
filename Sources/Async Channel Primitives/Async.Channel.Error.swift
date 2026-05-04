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

    extension Async.Channel where Element: ~Copyable {
        /// Errors that can occur during channel operations.
        public typealias Error = Async._ChannelError
    }

    extension Async {
        /// Errors that can occur during channel operations.
        ///
        /// Note: Defined at `Async` level (not inside generic `Channel<Element>`)
        /// to work around Swift compiler IRGen crash with typed throws + async + nested generic error types.
        public enum _ChannelError: Swift.Error, Sendable, Equatable {
            /// The channel has been closed.
            ///
            /// Thrown when attempting to send to a closed channel.
            case closed

            /// The operation was cancelled.
            ///
            /// Thrown when the task is cancelled while waiting.
            case cancelled

            /// The channel buffer is full.
            ///
            /// Thrown by immediate send when the buffer is full and the operation
            /// would need to suspend.
            case full

            /// The channel buffer is empty.
            ///
            /// Thrown by immediate receive when the buffer is empty and the operation
            /// would need to suspend.
            case empty
        }
    }

#endif  // !hasFeature(Embedded)
