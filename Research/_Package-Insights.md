# swift-async-primitives Insights

<!--
---
title: swift-async-primitives Insights
version: 1.0.0
last_updated: 2026-03-31
applies_to: [swift-async-primitives]
normative: false
---
-->

Design decisions, implementation patterns, and lessons learned specific to this package.

## Overview

This document captures insights that emerged during development of swift-async-primitives.
These are not API requirements — they are recorded decisions and patterns that inform
future work on this package.

**Document type**: Non-normative (recorded decisions, not requirements).

**Consolidation source**: Reflection entries tagged with `[package: swift-async-primitives]`.

---

## Slot-per-Send Overhead (2026-03-27)

**Date**: 2026-03-27

**Context**: The ~Copyable channel restructure replaced direct element capture in `withLock` closures with Slot-per-send staging (one `Ownership.Slot` heap allocation + two atomic CAS per send) due to the closure capture consumption limitation ([MEM-COPY-006] Category 6).

The Slot-per-send overhead on the fast path is non-zero: one class allocation per send. For high-throughput channels, this may be measurable. The overhead should be benchmarked against the pre-restructure direct element passing to quantify the cost and determine if optimization is warranted.

The end-state solution ([IMPL-070] coroutine Mutex) would eliminate the closure entirely, avoiding both the capture limitation and the Slot overhead. Until the coroutine Mutex is production-ready, the Slot approach is the correct implementation.

**Applies to**: Async.Channel.Bounded, Async.Channel.Unbounded, send/trySend hot paths

---

## Async.Mutex Sendable Constraint Cascade (2026-03-30)

**Date**: 2026-03-30

**Context**: `Async.Mutex<Value: ~Copyable & Sendable>` forces the `Sendable` constraint onto all channel State types — 7 `@unchecked Sendable` annotations exist solely to satisfy this. Stdlib's `Synchronization.Mutex` has no such constraint (uses `sending` for region transfer instead).

**Highest-leverage single change**: Refactor `Async.Mutex` to `Async.Mutex<Value: ~Copyable>` using `sending` for region transfer. This unblocks 7+ `@unchecked Sendable` removals in channel state types. Handoff written: `HANDOFF-async-mutex-sending-refactor.md`.

**Applies to**: Async.Mutex, all channel State types, Async.Channel.Bounded.State, Async.Channel.Unbounded.State

---

## Ownership.Slot.store() Discardable Result Warning (2026-03-30)

**Date**: 2026-03-30

**Context**: `Ownership.Slot.store()` returns the previously stored value (if any). In channel sender implementations, the return value is unused at 3 call sites, producing warnings. Options: (1) add `@discardableResult` to `Ownership.Slot.store()` in swift-ownership-primitives, or (2) use `_ = slot.store(element)` at each call site.

**Applies to**: Channel Sender types, Ownership.Slot
