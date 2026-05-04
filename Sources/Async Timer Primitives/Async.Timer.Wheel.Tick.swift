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

extension Async.Timer.Wheel {
    /// Integer representation of time in tick units.
    ///
    /// Ticks are counted from the wheel's epoch (captured at initialization).
    /// All internal time arithmetic uses ticks to avoid floating-point
    /// imprecision and Instant comparison overhead.
    ///
    /// With UInt64 and 1ms ticks, the wheel can represent ~584 million years.
    @usableFromInline
    typealias Tick = UInt64
}
