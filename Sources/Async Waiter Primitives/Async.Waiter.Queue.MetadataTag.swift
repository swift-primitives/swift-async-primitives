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

public import Identity_Primitives

extension Async.Waiter.Queue {
    /// Phantom tag for waiter metadata.
    public enum MetadataTag {}

    /// Caller-defined opaque metadata for waiter entries.
    ///
    /// Interpretation is entirely up to the caller. Common uses include
    /// slot indices, sequence numbers, or deadline timestamps. The Tagged
    /// wrapper prevents accidental mixing with other UInt64 values.
    public typealias Metadata = Tagged<MetadataTag, UInt64>
}
