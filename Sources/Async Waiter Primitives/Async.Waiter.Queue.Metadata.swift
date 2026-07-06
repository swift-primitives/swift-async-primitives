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

public import Tagged_Primitives

extension Async.Waiter.Queue {
    /// Caller-defined opaque metadata for waiter entries.
    ///
    /// Interpretation is entirely up to the caller. Common uses include
    /// slot indices, sequence numbers, or deadline timestamps. The Tagged
    /// wrapper prevents accidental mixing with other UInt64 values.
    ///
    /// `Async.Waiter.Queue` (the surrounding namespace) plays the phantom-tag
    /// role directly per [API-NAME-010a] — no separate `*Tag` marker type.
    public typealias Metadata = Tagged<Async.Waiter.Queue, UInt64>
}
