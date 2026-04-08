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

extension Async.Semaphore {
    /// Runtime statistics for semaphore monitoring.
    public struct Metrics: Sendable, Equatable {
        /// Total successful acquisitions.
        public var acquisitions: UInt64

        /// Total releases (signals).
        public var releases: UInt64

        /// Total timeouts (waiters that expired before acquiring).
        public var timeouts: UInt64

        /// Total cancellations (waiters cancelled before acquiring).
        public var cancellations: UInt64

        /// Peak number of permits held concurrently.
        public var peakOutstanding: Int

        /// Current number of permits held (capacity - available).
        public var currentOutstanding: Int

        /// Current number of tasks waiting for a permit.
        public var currentWaiters: Int

        /// Creates empty metrics.
        @usableFromInline
        init() {
            self.acquisitions = 0
            self.releases = 0
            self.timeouts = 0
            self.cancellations = 0
            self.peakOutstanding = 0
            self.currentOutstanding = 0
            self.currentWaiters = 0
        }
    }
}
