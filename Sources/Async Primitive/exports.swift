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

// `Async Primitive` declares the root `enum Async {}` plus the package's
// foundational, stdlib-only declarations. Zero external-package dependencies
// per [MOD-017]'s `{Domain} Primitive` invariant — this is what keeps the root
// universally cheap to import. External-dependency-bearing sub-namespaces live
// in their own targets per [MOD-031]; this file re-exports nothing.
