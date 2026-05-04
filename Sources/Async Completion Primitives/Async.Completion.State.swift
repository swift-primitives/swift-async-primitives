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

    public import Synchronization

    extension Async.Completion {
        /// Atomic state for CAS discipline.
        ///
        /// ## State Machine
        /// ```
        /// pending → running → completed
        ///                   → timedOut
        ///                   → cancelled
        ///                   → failed
        /// pending → cancelled
        /// pending → failed
        /// ```
        public enum State: UInt8, AtomicRepresentable, Sendable {
            /// Initial state - not yet started.
            case pending = 0

            /// Operation is running.
            case running = 1

            /// Operation completed successfully.
            case completed = 2

            /// Operation timed out.
            case timedOut = 3

            /// Operation was cancelled.
            case cancelled = 4

            /// Operation failed with error.
            case failed = 5
        }
    }

#endif  // !hasFeature(Embedded)
