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

/// Namespace for Swift concurrency and scheduling infrastructure.
///
/// Runtime provides primitives for coordinating concurrent execution:
/// - `Async.Bridge`: Sync-to-async handoff primitive
///
/// These primitives are policy-free building blocks. Lifecycle semantics
/// (shutdown, cancellation, etc.) are composed at higher layers.
public enum Async {}
public typealias _Async = Async
