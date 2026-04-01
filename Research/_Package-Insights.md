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

---

## Timer.Wheel.Storage.Free — Slab Free List (2026-03-31)

**Date**: 2026-03-31

**Context**: Code-surface audit revealed that `Timer.Wheel.Storage.Free` hand-rolls a slab free list. `Buffer.Slab` from swift-slab-primitives may be a better fit, potentially eliminating custom free-list management code.

Investigation deferred. Handoff written: `HANDOFF-storage-free-data-structure.md`.

**Applies to**: Timer.Wheel.Storage.Free, swift-slab-primitives

---

## @_optimize(none) Workarounds for CopyPropagation Crash (2026-03-31)

**Date**: 2026-03-31

**Context**: 7 channel functions have `@_optimize(none)` workarounds for a CopyPropagation crash on `switch consume` with ~Copyable enum tuple payloads. Root cause: SILGen `load [take]` on trivial fields (swiftlang/swift#85743, fixed by PR #85745, commit `e93ea1db266`). Verified fixed on Swift 6.4-dev.

When Xcode ships Swift 6.3.1+ or 6.4 containing the fix, remove all 7 `@_optimize(none)` annotations. Tracked in `Research/audit.md` follow-up actions.

**Applies to**: Async.Channel.Bounded (4 functions), Async.Channel.Unbounded (3 functions)

---

## nonisolated(nonsending) Satisfies AsyncIteratorProtocol (2026-03-31)

**Date**: 2026-03-31

**Context**: Empirically confirmed that `nonisolated(nonsending) func next()` (without the `isolation:` parameter) satisfies `AsyncIteratorProtocol`'s `next(isolation:)` requirement. Tested with the specific combination of typed throws (`throws(Async.Channel<Element>.Error)`), `~Copyable` `Element` constraint, and `@_optimize(none)` workaround co-present. Reference this session when migrating other `AsyncIteratorProtocol` conformances.

**Applies to**: Async.Channel.Bounded.AsyncIterator, Async.Channel.Unbounded.AsyncIterator, any future AsyncIteratorProtocol conformances

---

## Timer.Wheel Arena Migration Complete — Methods Unimplemented (2026-03-31)

**Date**: 2026-03-31

**Context**: Timer.Wheel.Storage migrated from hand-rolled free-list (`[Node?]` + `Free` + `generation: UInt32`) to `Buffer<Node>.Arena.Bounded`. The arena infrastructure (insert, free, isValid) is in place. However, `Timer.Wheel.schedule()`, `cancel()`, and `advance()` remain unimplemented stubs — they should now use `storage.insert()`, `storage.free()`, and `storage.isValid()`.

**Applies to**: Async.Timer.Wheel.schedule, cancel, advance

---

## Timer.Wheel Intrusive Linked List — Keep Current Design (2026-04-01)

**Date**: 2026-04-01

**Context**: Investigation confirmed that `List.Linked<E, 2>` from `List_Primitives` **cannot** replace Timer.Wheel's intrusive linked list. Two blocking gaps: (1) no `remove(at: Index)` for O(1) positional removal — the cursor/splice API is the #1 tracked gap in list-primitives; (2) no ABA protection — `Storage.Pool` has no generation tokens, so stale cancel handles would silently remove wrong timers. Additionally, ~384 independent lists sharing one `Buffer.Arena.Bounded` is well-supported by the arena but has no API path through `List.Linked`. The ~120 lines of manual list management (now on `Slot` as `append(_:in:)`/`remove(_:in:)`/`popFirst(in:)`) are justified.

**Reopen trigger**: If `List.Linked` gains a cursor/splice API AND `Storage.Pool` gains generation-based validation.

**Applies to**: Async.Timer.Wheel.Slot, Node, Storage types
