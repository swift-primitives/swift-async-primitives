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

/// Underscore-prefixed alias for ``Async``.
///
/// An escape hatch for call sites that need to spell the namespace when the
/// bare `Async` name is shadowed by a local declaration.
public typealias _Async = Async
