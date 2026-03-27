# Audit: swift-async-primitives

## Code Surface — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets
- **Skill**: code-surface — [API-NAME-001], [API-NAME-002], [API-NAME-003], [API-ERR-001], [API-IMPL-005]
- **Files**: 55 source files, 0 test files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [API-NAME-001] | Async.Timer.Wheel.ID.swift:17 | `_TimerWheelEntryTag` is a compound name — "TimerWheel" is redundant given `Async.Timer.Wheel` nesting. Also uses forbidden `Tag` suffix. Should be `_Entry` or similar. | RESOLVED 2026-03-27 |
| 2 | MEDIUM | [API-NAME-002] | Async.Lifecycle.swift:117 | `beginShutdown()` — public compound method. Nested accessor pattern: `shutdown.begin()` | OPEN |
| 3 | MEDIUM | [API-NAME-002] | Async.Lifecycle.swift:138 | `completeShutdown()` — public compound method. Nested accessor pattern: `shutdown.complete()` | OPEN |
| 4 | MEDIUM | [API-NAME-002] | Async.Lifecycle.swift:86 | `isShuttingDown` — public compound property. Nested accessor pattern: `shutdown.isActive` or `is.shuttingDown` | OPEN |
| 5 | MEDIUM | [API-NAME-002] | Async.Lifecycle.swift:94 | `isShutdownComplete` — public compound property. Nested accessor pattern: `shutdown.isComplete` or `is.complete` | OPEN |
| 6 | MEDIUM | [API-NAME-002] | Async.Completion.swift:138 | `setContinuation(_:)` — public compound method. Nested accessor pattern: `continuation.set(_:)` or initializer parameter | OPEN |
| 7 | MEDIUM | [API-IMPL-005] | Async.Channel.Bounded.State.swift | Contains 7+ type declarations: `State`, `Status`, `Sender`, `Receiver`, `Send` (+ `Action`, `Cancel`), `Receive` (+ `Action`, `Cancel`), `Close`. Should be split per type. | OPEN |
| 8 | MEDIUM | [API-IMPL-005] | Async.Channel.Unbounded.State.swift | Contains 5+ type declarations: `State`, `Slot`, `Send` (+ `Action`), `Receive` (+ `Step`, `Stop`, `Continuation`), `Close` | OPEN |
| 9 | MEDIUM | [API-IMPL-005] | Async.Broadcast.swift | Contains 3 public types spanning ~200 lines: `Broadcast`, `Subscription`, `Subscription.AsyncIterator`. Iterator alone is ~80 lines. | OPEN |
| 10 | LOW | [API-IMPL-005] | Async.Channel.Bounded.swift:100–178 | Contains `Bounded`, `Take`, `Ends` — three types in one file | OPEN |
| 11 | LOW | [API-IMPL-005] | Async.Channel.Unbounded.swift:100–179 | Contains `Unbounded`, `Take`, `Ends` — three types in one file | OPEN |
| 12 | LOW | [API-IMPL-005] | Async.Waiter.Queue.swift | Contains 6+ declarations: `Queue` namespace, `Bounded`/`Unbounded`/`Drain` typealiases, `MetadataTag`, `Metadata`, `Flagged`, `Flagged.Split` | OPEN |
| 13 | LOW | N/A | Async.Channel.Error.swift:1–6 | Xcode boilerplate header (`//  File.swift`) instead of standard project header | RESOLVED 2026-03-27 |

### Summary

13 findings: 0 critical, 0 high, 8 medium, 5 low.

**Systemic pattern — [API-IMPL-005]**: State machine files consistently bundle multiple tightly-coupled types. The bounded channel state file is the worst offender with 7+ types in 484 lines. This is the dominant convention gap across the package.

**Systemic pattern — [API-NAME-002]**: The `Lifecycle.State` type has 4 compound public API members. These predate the nested accessor convention and need migration.

[API-ERR-001] is fully satisfied — all throwing functions use typed throws. [API-NAME-003] is N/A. [API-NAME-001] is well followed with one exception.

---

## Implementation — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets
- **Skill**: implementation — [IMPL-*], [PATTERN-*]
- **Files**: 55 source files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | LOW | [API-NAME-002] | Async.Channel.Bounded.State.swift:122 | `popNextSender(resumeCancelled:)` — internal compound method without WORKAROUND annotation (compare `popEligible` which has one) | OPEN |
| 2 | LOW | [API-NAME-002] | Async.Channel.Bounded.State.swift:178,205,244,300,347,401 | Internal state machine methods `trySend`, `sendSuspended`, `sendCancelled`, `tryReceive`, `receiveSuspended`, `receiveCancelled` — compound names without WORKAROUND annotations | OPEN |
| 3 | LOW | [API-NAME-002] | Async.Timer.Wheel.Tick.swift:29 | `tickNumber(for:)` — `@inlinable` public method with compound name | OPEN |
| 4 | LOW | [API-NAME-002] | Async.Timer.Wheel.Config.swift:102,117 | `levelRange(_:)`, `ticksPerSlot(_:)` — `@inlinable` public methods with compound names | OPEN |
| 5 | LOW | [API-NAME-002] | Async.Timer.Wheel.Tick.swift:100 | `dividedRoundingDown(by:)` — public extension method on `Duration` with compound name | OPEN |
| 6 | LOW | [API-NAME-002] | Async.Broadcast.State.swift:60 | `minCursor()`, `pruneBuffer()` — internal compound methods | OPEN |

### Summary

6 findings: 0 critical, 0 high, 0 medium, 6 low.

Internal state machine methods consistently use compound names. The waiter queue extensions (`popEligible`, `reapFlagged`) have documented WORKAROUND annotations with tracking — the state machine methods lack this consistency. This is low severity because these are internal types, but adding WORKAROUND annotations would document intent.

The deferred-resumption pattern (compute under lock, resume outside) is consistently applied across all channel types. Expression-first style and typed throws are well used throughout.

---

## Modularization — 2026-03-27

### Scope

- **Target**: swift-async-primitives — package structure
- **Skill**: modularization — [MOD-*]
- **Files**: Package.swift, 6 targets

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|

No findings. Package structure is clean.

### Summary

0 findings.

Target decomposition is well-structured: Core provides shared types (Continuation, Mutex, Publication, Lifecycle, etc.), four variant targets provide independent functionality (Channel, Broadcast, Timer, Waiter), and an umbrella target re-exports all. Dependencies flow strictly downward — no lateral dependencies between variants. Each variant exports Core via `@_exported public import`, giving consumers transparent access to shared types.

---

## Memory Safety — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets
- **Skill**: memory-safety — [MEM-COPY-*], [MEM-OWN-*], [MEM-SAFE-*], [MEM-SEND-*]
- **Files**: 55 source files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | LOW | [MEM-SEND-*] | Async.Timer.Wheel.Storage.swift:38 | `Storage` is `@unchecked Sendable` — justified by single-actor design (Wheel is `~Copyable`), but relies on external discipline rather than type-system enforcement | OPEN |

### Summary

1 finding: 0 critical, 0 high, 0 medium, 1 low.

~Copyable types are used correctly throughout: `Entry`, `Resumption`, `Flagged`, `Flagged.Split` enforce single-use semantics; `Bounded`, `Receiver`, `Take`, `Ends` enforce channel identity; `Timer.Wheel` and `Storage` enforce single-owner semantics.

The `unsafe` keyword is used correctly as an expression keyword (not a block construct) in `Async.Continuation.Unsafe` and channel receiver implementations. The `@safe` annotation on `Continuation.Unsafe` concentrates unsafety at two sites (init + resume).

All `@unchecked Sendable` usages have documented justification (Mutex-protected internal state or atomic operations). `consuming func` is used appropriately on `Entry.resumption(with:)` and `Take.ends()`.

---

## Primitives — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets
- **Skill**: primitives — [PRIM-FOUND-001], [PRIM-*]
- **Files**: 55 source files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|

No findings.

### Summary

0 findings.

No Foundation imports anywhere in the package. All dependencies are on lower-tier primitives packages (`Buffer_Primitives`, `Queue_Primitives`, `Identity_Primitives`, `Dictionary_Primitives`, `Handle_Primitives`, `Ownership_Primitives`, `Kernel_Primitives`). Module naming uses the correct `-primitives` suffix convention. Downward-only tier dependency constraint is satisfied.

---

## Performance — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets (post-`53c9694e` bounded channel optimization)
- **Audit points**: heap allocations on hot paths, lock acquisition count, CoW traps, closure captures, redundant work inside locks
- **Files**: 55 source files

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | HIGH | PERF-ALLOC | Async.Broadcast.swift:108 | `Array(state.subscribers.keys)` inside lock on every `send()` — heap allocates a copy of all subscriber IDs. O(n) allocation per send where n = subscriber count. | RESOLVED 2026-03-27 |
| 2 | HIGH | PERF-ALLOC | Async.Broadcast.swift:183–184 | `Async.Publication<Wait>()` created on every `next()` call — allocates a `final class` with `Mutex` per element received. This is a heap allocation on every iteration step. | RESOLVED 2026-03-27 |
| 3 | MEDIUM | PERF-ALLOC | Async.Broadcast.swift:106 | `var toResume: [(CheckedContinuation<...>, Element)] = []` — Array allocation inside lock on every `send()`, even when no subscribers are waiting | RESOLVED 2026-03-27 |
| 4 | MEDIUM | PERF-LOCK | Async.Channel.Unbounded.Sender.swift:91–95 | `send(contentsOf:)` acquires and releases lock per element — O(n) lock acquisitions for n-element batch. Contrast with `Bridge.push(_: [Element])` which batches under single lock. | RESOLVED 2026-03-27 |
| 5 | LOW | PERF-ALLOC | Async.Barrier.swift:66 | `var waiters: [Async.Continuation<Void>] = []` — dynamic Array growth for barrier waiters. Party count is known at init; could pre-allocate `reserveCapacity(parties - 1)` | OPEN |
| 6 | LOW | PERF-ALLOC | Async.Broadcast.swift:149 | `Array(state.subscribers.keys)` repeated in `finish()` — same pattern as #1 but one-shot, so lower impact | RESOLVED 2026-03-27 |

### Additional Analysis

**CoW traps**: None found. The bounded channel's Phase enum has been correctly flattened to flat struct properties (post-`53c9694e`). The unbounded channel's `receive` accessor uses careful `_read`/`_modify` with explicit buffer uniqueness enforcement (`_buffer!.reserve(.zero)` + nil-out + defer restore). Timer wheel uses `withUnsafeMutableBufferPointer` for slot access. No enum-associated-value extraction patterns remain on hot paths.

**Lock acquisition counts** (per operation):

| Operation | Fast path | Slow path | Cancel |
|-----------|-----------|-----------|--------|
| Bounded send | 1 | 2 | +1 |
| Bounded receive | 1 | 2 | +1 |
| Bounded close | 1 | — | — |
| Unbounded send | 1 | — | — |
| Unbounded receive | 1 | 2 | +1 |
| Broadcast send | 1 | — | — |
| Broadcast next | 1 | 1 | +1 (up to +2 with early-cancel) |

All operation paths use minimal lock acquisitions. No excessive reacquisition patterns.

**Closure captures**: The `collectCancelled` closure in bounded `tryReceive()`/`receiveSuspended()` captures a local `var cancelled: Deque?` by reference. Since the closure parameter is non-escaping, the compiler can stack-allocate the capture box. No heap-forcing captures found on hot paths.

**Redundant work inside locks**: All channel types consistently follow the deferred-resumption pattern — compute outcomes under lock, resume continuations outside lock. No violations found. The bounded channel specifically collects cancelled sender continuations into a `Deque` under lock, then drains them outside. The broadcast channel builds a `toResume` array under lock, then iterates outside.

### Summary

6 findings: 0 critical, 2 high, 2 medium, 2 low. **5 resolved**, 1 open.

**Resolved — Broadcast per-element allocation** (#1, #2, #3): `send()` now uses `forEach` + targeted lookup instead of `Array(state.subscribers.keys)` snapshot — allocation is O(waking) not O(total). `Publication<Wait>` is now created once per `makeAsyncIterator()` and reused across `next()` calls (stale value cleared before each use). `finish()` uses the same `forEach` pattern (#6).

**Resolved — Unbounded batch send** (#4): `send(contentsOf:)` now processes all elements under a single lock acquisition. First element goes directly to a waiting receiver (if any); remaining elements buffer.

The bounded and unbounded channels are in good shape after the `53c9694e` optimization — flat state, no CoW traps, minimal allocations, single lock acquisitions on fast paths.
