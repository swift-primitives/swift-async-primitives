# Audit: swift-async-primitives

## Code Surface — 2026-03-31

### Scope

- **Target**: swift-async-primitives — all 12 source modules
- **Skill**: code-surface — full requirement set ([API-NAME-001–004], [API-ERR-001–005], [API-IMPL-003/005–011])
- **Files**: 62 source files (50 type/extension files, 12 export files)
- **Mode**: Strict — all access levels audited, no findings suppressed by visibility

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [API-NAME-001] | Async.Mutex.swift:19,27 | `_AsyncMutexValue`, `_AsyncMutexLock` — compound top-level names. Should be `Async.Mutex._Value`, `Async.Mutex._Lock`. Extraction may be blocked by `@_rawLayout` + `~Copyable` constraint interaction. | OPEN |
| 2 | MEDIUM | [API-NAME-002] | Async.Lifecycle.swift:86,94,117,138 | 4 compound public identifiers: `isShuttingDown`, `isShutdownComplete`, `beginShutdown()`, `completeShutdown()`. Nested accessor pattern: `shutdown.begin()`, `shutdown.complete()`, `shutdown.isActive`, `shutdown.isComplete`. | OPEN |
| 3 | MEDIUM | [API-NAME-002] | Async.Completion.swift:139,280 | `setContinuation(_:)` — compound public method (should be `continuation.set(_:)`). `currentState` — compound internal property. | OPEN |
| 4 | MEDIUM | [API-NAME-002] | Async.Promise.swift:127 | `fulfilledValue` — compound public property. Should be `fulfilled.value` or restructured via accessor. | OPEN |
| 5 | MEDIUM | [API-NAME-002] | Async.Barrier.swift:122 | `arrivedCount` — compound property on public type. Should be `arrived.count` or `arrived`. | OPEN |
| 6 | MEDIUM | [API-NAME-002] | Async.Timer.Wheel.Config.swift:108,112,119,164,178 | 5 compound public identifiers: `slotMask`, `slotShift`, `rangeTicks`, `levelRange(_:)`, `ticksPerSlot(_:)`. Should use nested accessor pattern (e.g., `slot.mask`, `slot.shift`, `level.range(_:)`). | OPEN |
| 7 | MEDIUM | [API-NAME-002] | Async.Timer.Wheel.Tick.swift:34,51,113 | 3 compound public methods: `tickNumber(for:)`, `currentSlot(level:)`, `dividedRoundingDown(by:)`. | OPEN |
| 8 | LOW | [API-NAME-002] | Async.Broadcast.State.swift:61,66 | `minCursor()`, `pruneBuffer()` — internal compound methods. | OPEN |
| 9 | LOW | [API-NAME-002] | Async.Timer.Wheel.Node.swift:32 | `deadlineTick` — internal compound stored property. | OPEN |
| 10 | LOW | [API-NAME-002] | Async.Timer.Wheel.Slot.swift:62,81,104,140 | 4 internal compound methods on `Wheel`: `withSlot`, `slotAppend`, `slotRemove`, `slotPopFirst`. Slot prefix acts as pseudo-namespace — should be nested accessor. | OPEN |
| 11 | LOW | [API-NAME-002] | Async.Timer.Wheel.Storage.swift:57,61 | `freeLinks`, `freeHead` — internal compound stored properties. Should use `Free` sub-struct or nested accessor. | OPEN |
| 12 | LOW | [API-NAME-002] | Async.Timer.Wheel.swift:87 | `minIndex` — internal compound stored property. | OPEN |
| 13 | MEDIUM | [API-IMPL-003] | Async.Channel.Unbounded.State.swift:36 | `_closed: Bool` — boolean flag where Bounded variant correctly uses `enum Status { open, closed, finished }`. Unbounded cannot represent "closed but draining" vs "finished" with a boolean. | OPEN |
| 14 | LOW | [API-IMPL-003] | Async.Broadcast.State.swift:49 | `Is.finished: Bool` — lifecycle flag. Could expand to `finishing`/`finished`. | OPEN |
| 15 | HIGH | [API-IMPL-005] | Async.Completion.swift | 5 type declarations: `Completion` (class), `Error` (enum), `State` (enum), `Transition` (enum), `Transition.Error` (enum). No ~Copyable exception. At minimum extract `Transition` + `Transition.Error`. | OPEN |
| 16 | HIGH | [API-IMPL-005] | Async.Broadcast.swift | 4 type declarations: `Broadcast` (class), `Buffer` (struct), `Subscription` (struct), `AsyncIterator` (struct). `Buffer` does not reference `Element` — can be cleanly extracted. `Element: Sendable` — no ~Copyable exception. | OPEN |
| 17 | MEDIUM | [API-IMPL-005] | Async.Lifecycle.swift | 2 types: `Lifecycle` (namespace enum) + `State` (enum). `State` should be in `Async.Lifecycle.State.swift`. | OPEN |
| 18 | MEDIUM | [API-IMPL-005] | Async.Continuation.swift | 2 types: `Continuation` (struct) + `Storage` (enum). `T: Sendable` is Copyable — no ~Copyable exception applies. | OPEN |
| 19 | MEDIUM | [API-IMPL-005] | Async.Promise.swift | `Gate = Promise<Void>` typealias + dedicated API surface (`open()`, `wait()`, `isOpen`). Effectively a separate concept — extract to `Async.Gate.swift`. | OPEN |
| 20 | MEDIUM | [API-IMPL-005] | Async.Mutex.swift:19,27,56 | 3 types: `_AsyncMutexValue`, `_AsyncMutexLock`, `Mutex`. The `@_rawLayout` types reference `Value: ~Copyable` — extraction may be blocked by constraint interaction. Needs verification. | OPEN |
| 21 | MEDIUM | [API-IMPL-005] | Async.Channel.Bounded.swift | 3 types: `Bounded`, `Take`, `Ends`. ~Copyable `Element` context — verify extractability. | OPEN |
| 22 | MEDIUM | [API-IMPL-005] | Async.Channel.Bounded.Receiver.swift | 4 types: `Receiver`, `Receive`, `Elements`, `Iterator`. ~Copyable context. | OPEN |
| 23 | MEDIUM | [API-IMPL-005] | Async.Channel.Bounded.Sender.swift | 3 types: `Sender`, `Handle` (class w/ deinit), `Send`. `Handle` justified (~Copyable + deinit), but `Send` should be extractable. | OPEN |
| 24 | MEDIUM | [API-IMPL-005] | Async.Channel.Unbounded.swift | 3 types: `Unbounded`, `Take`, `Ends`. ~Copyable context. | OPEN |
| 25 | MEDIUM | [API-IMPL-005] | Async.Channel.Unbounded.Receiver.swift | 3 types: `Receiver`, `Elements`, `Iterator`. ~Copyable context. | OPEN |
| 26 | MEDIUM | [API-IMPL-005] | Async.Broadcast.State.swift | 4 types: `State`, `NextIndex`, `SubscriberID`, `Is`. `Element: Sendable` — no ~Copyable exception. | OPEN |
| 27 | MEDIUM | [API-IMPL-005] | Async.Waiter.Queue.swift | 4 types: `Queue`, `MetadataTag`, `Flagged`, `Split`. `Split` may stay with `Flagged` (~Copyable `Metadata` parameter). | OPEN |
| 28 | LOW | [API-IMPL-005] | Async.Broadcast.Next.Outcome.swift | 2 types: `Next` (namespace) + `Outcome`. Extract `Next` to `Async.Broadcast.Next.swift`. | OPEN |
| 29 | LOW | [API-IMPL-005] | Async.Broadcast.Subscriber.swift | 2 types: `Subscriber` + `Wait`. Extract `Wait` to `Async.Broadcast.Wait.swift`. | OPEN |
| 30 | LOW | [API-IMPL-005] | Async.Waiter.Flag.swift | 2 types: `Flag` (class) + `Reason` (enum). Extract to `Async.Waiter.Flag.Reason.swift`. | OPEN |
| 31 | MEDIUM | [API-IMPL-007] | Async.Timer.Wheel.Slot.swift:51–145 | Extensions on `Async.Timer.Wheel` (not `Slot`) in file named `Slot`. Should be in `Async.Timer.Wheel+Slot.swift`. | OPEN |
| 32 | MEDIUM | [API-IMPL-007] | Async.Timer.Wheel.Tick.swift:26–185 | Extensions on `Wheel` and `Duration` in file named for `Tick` typealias. Wheel methods → `Async.Timer.Wheel+Tick.swift`; Duration extension → `Duration+Tick.swift`. | OPEN |
| 33 | HIGH | [API-IMPL-008] | 20 files systemic | Methods and computed properties in type bodies instead of extensions. **Worst offenders**: Async.Waiter.Flag.swift (6 members), Async.Bridge.swift (4 methods), Async.Promise.swift (4 methods), Async.Barrier.swift (3 methods), Async.Channel.Bounded.Storage.swift (3 methods), Async.Channel.Unbounded.Storage.swift (2 methods), Async.Callback.swift (3 methods + convenience init). **Also affected**: Async.Continuation.swift, Async.Continuation.Unsafe.swift, Async.Completion.swift, Async.Channel.Bounded.swift, Async.Channel.Bounded.Receiver.swift, Async.Channel.Unbounded.swift, Async.Channel.Unbounded.Receiver.swift, Async.Broadcast.swift, Async.Waiter.Entry.swift, Async.Waiter.Queue.swift, Async.Waiter.Resumption.swift, Async.Timer.Wheel.Slot.swift, Async.Mutex.swift (embedded branch). | OPEN |

### Justified Exceptions

| Location | Rule | Justification |
|----------|------|---------------|
| Async.Channel.Bounded.State.swift | [API-IMPL-005] | 7+ types — all reference `Element: ~Copyable` through extension constraint. [MEM-COPY-006] exception applies. Methods correctly placed in extensions. |
| Async.Channel.Unbounded.State.swift | [API-IMPL-005] | 5+ types — same `~Copyable` constraint poisoning justification as Bounded.State. |
| Async.Channel.Error.swift | [API-IMPL-005] | 2 declarations (`typealias Error` + `enum _ChannelError`) — hoisted pattern per [API-IMPL-009] due to documented IRGen crash on generic-nested error types. |
| Queue+Async.Waiter.swift | [API-NAME-002] | `popEligible`, `reapFlagged` — documented WORKAROUND annotations with tracked removal criteria. |
| Queue.Fixed+Async.Waiter.swift | [API-NAME-002] | Same documented workaround as above. |

### Rules Passing Clean

| Rule | Assessment |
|------|-----------|
| [API-NAME-003] | N/A — no specification implementations in this package |
| [API-NAME-004] | Pass — no typealias-for-unification bridges. `Gate = Promise<Void>` is a valid specialization alias per [PATTERN-024]. |
| [API-ERR-001] | **Pass** — all throwing functions use typed throws (`throws(Async.Channel<Element>.Error)`, `throws(Transition.Error)`, `throws(E)` on generic wrappers). Zero untyped `throws`. |
| [API-ERR-002] | **Pass** — all error types nested as `Domain.Error`: `Async.Channel.Error`, `Async.Broadcast.Error`, `Async.Completion.Error`, `Async.Completion.Transition.Error`. |
| [API-ERR-003] | **Pass** — all error cases describe failure conditions (`closed`, `cancelled`, `full`, `empty`, `timeout`, `alreadyDone`). |
| [API-ERR-004] | **Pass** — typed throws closure annotations present where required (e.g., `Async.Mutex.withLock`, `Async.Channel.Bounded.Storage.withLock`). |
| [API-ERR-005] | **Pass** — no `@_disfavoredOverload` workarounds for stdlib typed throws. |
| [API-IMPL-009] | **Pass** — hoisted protocol pattern used correctly for `Async.Channel.Error` (IRGen crash workaround). |

### Summary

33 findings: 0 critical, 3 high, 16 medium, 14 low.

**Systemic pattern #1 — [API-IMPL-008] (HIGH, 20 files)**: Methods and computed properties in type bodies is the dominant convention gap. Only `Async.Publication.swift` and `Async.Mutex.Locked.swift` correctly separate stored properties from behavior. Every other type-declaring file has at least one method or computed property inside the type body. This is a mechanical fix — extract methods to extensions — but touches 20 of 50 type files.

**Systemic pattern #2 — [API-IMPL-005] (16 files)**: Multi-type files. Three categories: (a) Broadcast and Completion types (no ~Copyable excuse, clearly extractable), (b) Channel types (~Copyable context — extraction needs verification against constraint poisoning), (c) small namespace+type bundles (low severity, mechanical extraction).

**Systemic pattern #3 — [API-NAME-002] (11 files, ~30 instances)**: Compound identifiers cluster in two areas: Lifecycle public API (4 members) and Timer.Wheel internals (~16 identifiers). Timer.Wheel predates the nested accessor convention and has the highest density of compound names in the package.

**Compared to prior audit (2026-03-27)**: This strict re-audit expanded from 5 checked rules to the full code-surface requirement set. New findings: [API-IMPL-008] was not previously audited and accounts for 1 HIGH systemic finding covering 20 files. [API-IMPL-003] and [API-IMPL-007] are also new. Prior findings 7–8 (Channel State files) reclassified as justified exceptions per [MEM-COPY-006]. Prior findings 1 and 13 remain RESOLVED.

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

The `inout Element?` send-path pattern (bounded/unbounded channels) is ownership-correct: `element.take()!` is only called on paths where the Optional is guaranteed non-nil by control flow, and the `inout` reference passes safely through non-escaping `withLock` closures without ownership violations. The `.take()!` idiom (not `!`) avoids a known Swift 6.3 IRGen crash on force-unwrap of `var Optional<~Copyable>` into a generic `consuming` parameter.

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

## Platform — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets
- **Skill**: platform — [PLAT-ARCH-*], [PATTERN-001–008]
- **Files**: 55 source files, Package.swift

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|

No findings.

### Summary

0 findings.

`#if !hasFeature(Embedded)` is used consistently across all async-suspension-dependent code (channels, broadcast, bridge, continuation). This is correct — `withUnsafeContinuation` and `withCheckedContinuation` are unavailable on embedded Swift. Non-suspension code (Lifecycle, Publication, Callback value paths) is unconditionally available.

Package.swift correctly uses `.when(platforms:)` conditional for Kernel Primitives dependency (platform-specific). Swift settings include `.strictMemorySafety()`, `ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`, `NonisolatedNonsendingByDefault`, `Lifetimes`, `SuppressedAssociatedTypes` — consistent with ecosystem conventions. Swift language mode is v6. Swift tools version is 6.2.

---

## Testing — 2026-03-27

### Scope

- **Target**: swift-async-primitives — test target
- **Skill**: testing — [TEST-*], testing-swiftlang — [SWIFT-TEST-*]
- **Files**: 6 test files, 1 test support module

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | HIGH | [TEST-*] | Tests/ | No tests for Async Timer Primitives — Timer.Wheel is a multi-level hierarchical timer with tick computation, level promotion, slot management, and node lifecycle. Zero test coverage. | OPEN |
| 2 | HIGH | [TEST-*] | Tests/ | No tests for Async Waiter Primitives — Waiter.Queue supports bounded/unbounded variants with two-phase suspension, flag-based filtering, and lazy skip. Zero test coverage. | OPEN |
| 3 | MEDIUM | [TEST-*] | Tests/ | No dedicated tests for Core types: Bridge, Completion, Lifecycle, Promise, Precedence, Barrier, Mutex. Some exercised indirectly (Barrier as test synchronization util, Bridge in Publication stress tests via Unbounded channel) but no targeted coverage. | OPEN |
| 4 | MEDIUM | [SWIFT-TEST-*] | Async.Channel.Bounded Tests.swift | Flat `@Suite struct BoundedChannelTests` without nested Unit/EdgeCase/Integration/Performance categorization. Contrast with Callback and Publication tests which use the nested `{Type}.Test.{Category}` pattern. | OPEN |
| 5 | MEDIUM | [SWIFT-TEST-*] | Async.Channel.Unbounded Tests.swift | Same flat structure as bounded channel tests. Should follow nested pattern. | OPEN |
| 6 | MEDIUM | [SWIFT-TEST-*] | Async.Broadcast Tests.swift | Two separate top-level suites (`BroadcastTests`, `BroadcastStressTests`) instead of nested `Broadcast.Test.Unit` / `Broadcast.Test.Stress` pattern. | OPEN |
| 7 | MEDIUM | [TEST-*] | Async.Channel.Bounded Tests.swift | No explicit cancellation test for bounded sender. The `sendCancelled` path with lazy-skip and the `onCancel` handler in `send()` are never directly tested. Contrast with UnboundedChannelTests which has `Cancellation throws cancelled error`. | OPEN |
| 8 | MEDIUM | [TEST-*] | Async.Channel.Bounded Tests.swift:267 | "Auto-close when sender drops" test is incomplete — comment at line 280 says "The test needs restructuring". Test creates `ends` before sender drops, keeping the handle alive via `ends.sender`, so auto-close is never actually triggered and verified. | OPEN |

### Summary

8 findings: 0 critical, 2 high, 6 medium, 0 low.

**Coverage gap — Timer and Waiter** (Findings #1–2): Two of six source targets have zero test coverage. Timer.Wheel is particularly complex (multi-level promotion, tick arithmetic, node lifecycle) and Waiter.Queue has subtle concurrency semantics (two-phase suspension, flag-based filtering). These represent the largest testing gap in the package.

**Coverage gap — Core types** (Finding #3): Bridge, Completion, Lifecycle, Promise, Barrier, Precedence, and Mutex lack dedicated tests. While some are exercised indirectly, this is insufficient for correctness confidence on infrastructure code.

**Structural inconsistency** (Findings #4–6): Channel and Broadcast tests use flat suite organization while Callback and Publication tests use the proper nested `{Type}.Test.{Category}` pattern. The nested pattern enables selective test execution by category and provides clearer organization.

**Bounded channel gaps** (Findings #7–8): Missing cancellation test and incomplete auto-close test leave two important bounded channel behaviors unverified.

**Positive observations**: Test names are descriptive and backtick-quoted. `#expect` assertions used throughout (no XCTAssert). Stress tests use iteration (rounds) for statistical confidence. `Async.Barrier` used for deterministic task synchronization instead of arbitrary sleeps. Typed `do throws(...)` used for error-type assertions. Test support module re-exports all dependencies cleanly.

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

---

## Zero-Copy Pipeline — 2026-03-27

### Scope

- **Target**: swift-async-primitives — all 6 source targets
- **Audit points**: zero-copy element transfer, ownership annotations, ~Copyable/~Sendable feasibility, `@concurrent`/`nonisolated(nonsending)` correctness, `consuming`/`borrowing` gaps, `~Escapable` applicability
- **Prior research consulted**: `sending-expansion-audit.md` (COMPLETE), `zero-copy-event-pipeline.md` (RECOMMENDATION), `concurrent-expansion-audit.md` (COMPLETE), `nonsending-adoption-audit.md` (COMPLETE), `witness-macro-noncopyable-support-design.md` (RECOMMENDATION), `async-pool-primitives-audit.md` (RECOMMENDATION)
- **Files**: 55 source files (element-carrying hot paths prioritized)

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | HIGH | PERF-COPY | Async.Continuation.swift:60, Async.Continuation.Unsafe.swift:43 | `resume(returning value: T)` takes `value` by default convention (owned), not `consuming`. The stdlib `UnsafeContinuation.resume(returning: consuming sending T)` takes `consuming`. This creates a copy at the wrapper → stdlib boundary for every element delivery across all channel types. | RESOLVED 2026-03-27 |
| 2 | HIGH | PERF-COPY | Async.Channel.Bounded.State.swift:266 | Receive continuation type is `Async.Continuation<(Element?, Error?)>.Unsafe` — every element delivery wraps in Optional then constructs a 2-element tuple. The unbounded channel has the same pattern (State.swift:123). Contrast with Broadcast's `Next.Outcome` enum which avoids Optional wrapping entirely. | RESOLVED 2026-03-27 |
| 3 | MEDIUM | PERF-COPY | Async.Channel.Bounded.State.swift:76–94 | `State.Sender` bundles `element: Element` with `id` and `continuation` as `let` fields. When a suspended sender is popped at :316/:324, `sender.element` reads a `let` field from a live struct — this is a copy, not a move. The element cannot be consumed independently of the struct. | RESOLVED 2026-03-27 — Restructure stores `Ownership.Slot<Element>` (Copyable reference) instead of `Element`. Reading `sender.slot` copies a reference (trivial); `slot.take(__unchecked:)` moves the element via atomic CAS + pointer move. Zero copies regardless of Sender struct lifetime. |
| 4 | MEDIUM | PERF-COPY | Async.Channel.Bounded.State.swift:149, Unbounded.State.swift:83,100 | Action enum associated values carry `Element` through the lock boundary. `Send.Action.deliverToReceiver(_, Element)` and `Receive.Action.returnElement(Element, _, _)` store the element, then the caller pattern-matches it out. For Copyable types, enum extraction creates a binding copy; the optimizer should eliminate it in -O, but is not guaranteed to. | IMPROVED 2026-03-27 — All fast-path switches use `switch consume`, forcing destructive extraction for ~Copyable. Optimizer-dependent for Copyable unchanged. |
| 5 | MEDIUM | PERF-COPY | Async.Broadcast.swift:133–148 | `toResume` array copies `element` once per waiting subscriber: `toResume.append((cont, element))`. For fan-out to N>1 subscribers, N-1 copies are inherent. But for the single-subscriber fast path, the copy into the array is avoidable — could deliver directly without array intermediary. | OPEN |
| 6 | MEDIUM | [MEM-OWN-001] | Async.Channel.Bounded.State.swift:178, Unbounded.State.swift:94 | `trySend(_ element: Element)` and `send(_ element: Element)` take `element` by default owned convention, not `consuming`. Adding `consuming` would make the ownership transfer explicit and eliminate any caller-side retain for Copyable types with heap storage (arrays, strings). | RESOLVED 2026-03-27 |
| 7 | LOW | PERF-COPY | Async.Bridge.swift:84–98 | `push(_ element: sending Element)` has a double-delivery pattern: element is captured in the `withLock` closure, but on the direct-to-continuation path, `element` is also passed to `continuationToResume?.resume(returning: element)` outside the lock. The same `element` binding is used in both the buffer path and the resume path, which is correct (only one executes) but the binding crosses the lock boundary in both cases. Not a copy — compiler can prove mutual exclusion — but the pattern is fragile. | OPEN |
| 8 | LOW | N/A | All channel types | `Element: Sendable` constraint on `Async.Channel<Element: Sendable>` does NOT force copies at isolation boundaries. The `sending` annotation on public `send()` methods transfers ownership without requiring a Sendable-conformance-induced copy. `Sendable` is a capability constraint (allowing cross-isolation transfer), not a copy trigger. | FALSE_POSITIVE — Sendable is a static constraint, not a runtime copy mechanism |
| 9 | LOW | N/A | All types | `~Escapable` is not applicable to channel element types. Channels transfer ownership from producer to consumer — the element must escape the channel scope. `~Escapable` enforces the opposite invariant (preventing escape). Could theoretically apply to iterator/subscription types to prevent outliving the channel, but that would conflict with `AsyncSequence` conformance requirements. | FALSE_POSITIVE — Fundamentally opposed to channel ownership semantics |

### Element Pipeline Traces

#### Trace 1: Bounded Channel — Direct Delivery (fast path)

```
Sender.send(_ element: sending Element)                     ← sending: ownership transferred from caller
  └─ storage.withLock { state.trySend(element) }            ← element passed owned into closure, then into mutating func
       └─ State.trySend(_ element: Element)                 ← default owned convention (Finding #6)
            └─ .deliverToReceiver(receiver.continuation, element)  ← element MOVED into enum associated value
  └─ case .deliverToReceiver(let receiverCont, let element) ← element EXTRACTED from enum (Finding #4)
       └─ receiverCont.resume(returning: (element, nil))    ← element wrapped in Optional + tuple (Finding #2)
            └─ _base.resume(returning: value)               ← value COPIED from wrapper to stdlib (Finding #1)
                 └─ UnsafeContinuation resumes receiver task
```

**Copies on this path**: 2 certain (wrapper→stdlib at resume, tuple construction), 1 optimizer-dependent (enum extraction).

#### Trace 2: Bounded Channel — Buffered Path

```
Sender.send → state.trySend(element)
  └─ buffer.back.push(element)          ← Deque.push takes `consuming Element` — MOVE ✅
... later ...
Receiver.receive → state.tryReceive()
  └─ buffer.front.take                  ← Deque.take destructively removes — MOVE ✅
  └─ .returnElement(element, ...)       ← element MOVED into Action enum
  └─ case .returnElement(let element, ...):
       └─ return element                ← on fast path, returned directly — NO tuple wrapping ✅
```

**Copies on this path**: 0-1 (enum extraction only, optimizer-dependent). This is the cleanest path because the fast-path return in `Receiver.receive()` destructures the Action directly and returns the element without going through a continuation tuple.

#### Trace 3: Bounded Channel — Sender Suspension Path

```
Sender.send → state.sendSuspended(id:, element:, continuation:)
  └─ Sender(id: id, element: element, continuation: continuation)  ← element MOVED into struct
  └─ senders.back.push(Sender(...))                                ← Sender struct MOVED into Deque ✅
... later ...
Receiver.receive → state.tryReceive()
  └─ popNextSender(resumeCancelled:)
       └─ senders.front.take                     ← Sender struct MOVED out of Deque ✅
  └─ sender.element                              ← COPY — `let` field read from live struct (Finding #3)
  └─ .returnElement(sender.element, sender.continuation, ...)
```

**Copies on this path**: 1 certain (`sender.element` read from struct that is still alive for its `.continuation` field), plus enum extraction.

#### Trace 4: Unbounded Channel — Direct Delivery

```
Sender.send(_ element: sending Element)
  └─ state.send(element)
       └─ .give(cont, element)                         ← element MOVED into enum
  └─ case .give(let cont, let element):
       └─ cont.resume(returning: (element, nil))        ← Optional + tuple wrapping (Finding #2)
            └─ _base.resume(returning: value)            ← wrapper→stdlib copy (Finding #1)
```

**Copies on this path**: Same as Bounded direct delivery — 2 certain, 1 optimizer-dependent.

#### Trace 5: Unbounded Channel — Buffered + Fast Receive

```
Sender.send → state.send(element)
  └─ buffer.back.push(element)       ← MOVE into Deque ✅
... later ...
Receiver.receive → state.receive.take()
  └─ base.buffer.front.take          ← MOVE out of Deque ✅
  └─ .val(element)                   ← MOVE into Step enum
  └─ case .val(let element):
       └─ return element             ← returned directly, no tuple ✅
```

**Copies on this path**: 0-1 (enum extraction only). Cleanest path in the package — the unbounded fast receive avoids the tuple entirely.

#### Trace 6: Unbounded Channel — Slow Receive (Suspension)

```
Receiver.receive → withUnsafeContinuation { ... }
  └─ state.receive.wait(continuation)
       └─ base.slot = .wait(cont)     ← continuation stored
... later (sender arrives) ...
Sender.send → state.send(element)
  └─ .give(cont, element)
  └─ cont.resume(returning: (element, nil))    ← tuple wrapping (Finding #2), then stdlib copy (Finding #1)
... receiver resumes ...
  └─ let (element, error) = await ...
       └─ return element
```

**Copies on this path**: 2 certain (tuple construction, wrapper→stdlib), 1 optimizer-dependent (enum extraction). The slow path always goes through the tuple continuation.

#### Trace 7: Broadcast — Buffer + Fan-Out

```
Broadcast.send(_ element: sending Element)
  └─ state.buffer.back.push((index, element))   ← element MOVED into (UInt64, Element) tuple in Deque ✅
  └─ for each waiting subscriber at cursor:
       └─ toResume.append((cont, element))       ← element COPIED from buffer into array (Finding #5)
  └─ for (continuation, element) in continuationsToResume:
       └─ continuation.resume(returning: .element(element))  ← element moved into Outcome enum, then stdlib delivers
```

**Copies on this path**: N copies where N = waiting subscriber count. For N=0 (all subscribers reading from buffer later), zero copies at send time. For N=1, one copy is avoidable. For N>1, N-1 copies are inherent (fan-out). Buffer-path reads via `first(where:)` also copy the element out of the buffer (the element must stay for other subscribers).

#### Trace 8: Bridge — Push to Next

```
Bridge.push(_ element: sending Element)
  └─ if cont exists: return cont outside lock, resume with element  ← element crosses lock boundary by capture, then COPIED at wrapper→stdlib
  └─ else: state.buffer.back.push(element)                          ← MOVE into Deque ✅
... later ...
Bridge.next() async
  └─ state.buffer.front.take          ← MOVE out of Deque ✅
  └─ return (false, .some(element))   ← wrapped in (Bool, Element??) control tuple
  └─ continuation.resume(returning: immediateResult ?? nil)  ← CheckedContinuation (stdlib) resume
```

**Copies on this path**: 1-2. The `(Bool, Element??)` double-Optional control tuple is a minor overhead on the fast path. The main cost is the CheckedContinuation resume.

### Audit Point Answers

**Q: `sending` parameter → buffer insertion: is the element moved or copied?**
**A**: **Moved.** All public `send()` methods use `sending` (applied per prior `sending-expansion-audit.md`). `Deque.push(_ element: consuming Element)` takes ownership. The element flows: `sending` → owned parameter → `consuming` push. Zero copies on this segment.

**Q: Buffer extraction → continuation resume: is the element moved or copied?**
**A**: **1-2 copies.** `Deque.take` moves the element out (zero-copy). But delivery to the receiver continuation involves: (a) wrapping in `(Element?, Error?)` tuple for bounded/unbounded channels (1 copy for Optional + tuple construction), and (b) copy from `Continuation.resume(returning:)` wrapper to stdlib `UnsafeContinuation.resume(returning: consuming sending T)` (1 copy due to missing `consuming` annotation).

**Q: State machine action enums with associated values: extract-reconstruct cycles?**
**A**: **No extract-reconstruct cycles.** State is stored as flat properties (post-`53c9694e`). Action enums are constructed fresh on each operation and consumed by the caller. The enum is never stored back into state. Pattern-matching extraction creates bindings that may copy for Copyable types, but the optimizer should eliminate this in release builds since the enum is consumed.

**Q: Deque push/take: does the queue primitive support move semantics?**
**A**: **Yes.** `Deque<Element: ~Copyable>` is fully supported. `push(_ element: consuming Element)` moves in. `take(from:) -> Element?` destructively removes and returns owned. The ring buffer implementation uses pointer-based move operations internally. Zero copies in the Deque layer.

**Q: Continuation.resume(returning:) → caller: any intermediate copies?**
**A**: **Yes — 1 copy.** `Async.Continuation.resume(returning value: T)` and `Async.Continuation.Unsafe.resume(returning value: T)` both take `value` by default owned convention. The stdlib counterparts take `consuming sending`. The wrapper creates a copy at the handoff boundary. This is the single most impactful copy in the entire pipeline — it affects every element delivery across all channel types.

**Q: Tuple wrapping `(Element, Error?)` for receiver continuations: forced copies?**
**A**: **Yes — 1 copy.** The bounded and unbounded channels use `Continuation<(Element?, Async.Channel<Element>.Error?)>.Unsafe` for receiver continuations. On the success path, the element is wrapped into `.some(element)` then combined with `.none` for the error field. This tuple construction copies the element into the new composite value. The Broadcast avoids this by using `Next.Outcome` enum with `.element(Element)` — no Optional wrapping.

**Q: `Element: Sendable` constraint: does this force copies at isolation boundaries?**
**A**: **No.** `Sendable` is a static type-system constraint that enables cross-isolation transfer — it does not cause runtime copies. The `sending` annotation on `send()` parameters expresses the ownership transfer. At the implementation level, elements flow through a Mutex-protected state machine; there is no actor hop or isolation boundary crossing that would force a copy. The copies that exist are structural (tuple wrapping, enum extraction, continuation wrapper) rather than Sendable-induced.

### ~Copyable Element Feasibility

Can `Element` be `~Copyable`? **Not yet — blocked by 1 genuine constraint** (revised from 5 after stdlib research):

| # | Claimed Blocker | Actual Status | Evidence |
|---|----------------|---------------|----------|
| 1 | `Async.Channel<Element: Sendable>` — Sendable implies Copyable | **FALSE** | `Sendable` does NOT imply `Copyable`. Types can be `~Copyable & Sendable` (e.g., `Async.Waiter.Resumption`, stdlib `Job`). |
| 2 | `Async.Continuation<T: Sendable>` | **FALSE** | Under our control. Can be relaxed to `T: ~Copyable & Sendable`. |
| 3 | `UnsafeContinuation<T>` / `CheckedContinuation<T>` — implicit `Copyable` | **GENUINE** | Stdlib `T` has implicit `Copyable` (not explicit `Sendable`). Cannot be changed without stdlib evolution. |
| 4 | `Optional` wrapping | **FALSE** | `Optional<Wrapped: ~Copyable & ~Escapable>` fully supported in stdlib since Swift 6.0. |
| 5 | Enum associated values | **FALSE** | Fully supported. `Optional` and `Result` both use `~Copyable` associated values in stdlib. |

**1 genuine blocker**: The implicit `Copyable` constraint on `UnsafeContinuation<T>` and `CheckedContinuation<T>` generic parameters. The compiler infrastructure already supports `Continuation<T: ~Copyable>` (proven by test case at `swiftlang/swift/test/ModuleInterface/Inputs/NoncopyableGenerics_Misc.swift:142`), but the stdlib types have not been updated.

**Full analysis**: See `Research/zero-copy-noncopyable-element-feasibility.md` (RECOMMENDATION). Recommends preparing internal constraints now and submitting a Swift Evolution pitch for stdlib continuation relaxation.

### ~Sendable Element with `sending` Transfer

Can `Element` be `~Sendable` with `sending` transfer? **No — blocked by Mutex and state machine storage.**

The stdlib continuation types do NOT require explicit `T: Sendable` (contrary to the initial analysis). The `with*Continuation` functions return `sending T`, which allows non-Sendable types via region-based transfer. However:

1. `Mutex<State>` requires `State: Sendable`, which requires all stored element fields (buffer, sender queue) to be `Sendable`
2. The `@Sendable` `onCancel` closure in `withTaskCancellationHandler` requires captured values to be `Sendable` — `storage` is `Sendable` independently of `Element`, but the constraint propagates through the state
3. `Deque<Element>: Sendable` requires `Element: Sendable`

The constraint chain is: `Mutex<State: Sendable>` → `State.buffer: Deque<Element>` → `Deque: Sendable where Element: Sendable` → `Element: Sendable`.

A `sending`-only approach would require restructuring the state machine to not store elements in `Sendable`-conforming types — fundamentally incompatible with the Mutex-protected shared state design. **DEFERRED** — would require a radically different architecture (e.g., actor-based rather than Mutex-based).

### @concurrent / nonisolated(nonsending) Correctness

All async entry points audited — **no findings**. Summary:

| Method | Annotation | Correct? |
|--------|-----------|----------|
| `Bounded.Sender.send()` | `nonisolated(nonsending)` | ✅ Inherits caller isolation; work under Mutex, no executor hop |
| `Bounded.Receiver.receive()` | `isolation: isolated (any Actor)? = #isolation` | ✅ SE-0421 pattern |
| `Unbounded.Receiver.receive()` | `isolation: isolated (any Actor)? = #isolation` | ✅ SE-0421 pattern |
| `Bridge.next()` | `nonisolated(nonsending)` | ✅ Inherits caller isolation |
| `Promise.value()` | `nonisolated(nonsending)` | ✅ Inherits caller isolation |
| `Broadcast...next()` | `isolation: isolated (any Actor)? = #isolation` | ✅ SE-0421 pattern |
| All Elements.Iterator.next() | `isolation: isolated (any Actor)? = #isolation` | ✅ SE-0421 pattern |

Consistent with `concurrent-expansion-audit.md` which found no `@concurrent` candidates in this package — all methods use Mutex-protected state with continuation-based suspension, never hopping to a different executor.

### Proposed Fixes

**Fix A — `consuming` on Continuation.resume (addresses Finding #1)**

Highest-impact, lowest-risk change. Eliminates one copy on every element delivery across all types.

```swift
// Async.Continuation.swift:60
public func resume(returning value: consuming T) {
    switch storage {
    case .checkedContinuation(let continuation):
        continuation.resume(returning: value)
    case .callback(let callback):
        callback(value)
    }
}

// Async.Continuation.Unsafe.swift:43
public func resume(returning value: consuming T) {
    unsafe _base.resume(returning: value)
}
```

**Risk**: Low. The `consuming` annotation matches the stdlib contract. All existing call sites pass owned values that are not used after the call. `@inlinable` visibility means callers can see the consuming annotation and skip the retain.

**Fix B — Tri-state receive outcome enum (addresses Findings #2 and #4 partial)**

Replace `(Element?, Error?)` tuple with a dedicated enum for bounded/unbounded channel receivers.

```swift
// New type alongside existing Action enums
extension Async.Channel.Bounded.State.Receive {
    @usableFromInline
    enum Outcome: Sendable {
        case element(Element)
        case closed
        case cancelled
    }

    // Replace: typealias Continuation = Async.Continuation<(Element?, Error?)>.Unsafe
    // With:    typealias Continuation = Async.Continuation<Outcome>.Unsafe
}
```

**Risk**: Medium. Requires updating all resume sites and the receive-side destructuring. The Broadcast already uses this pattern (`Next.Outcome`), so there's prior art in the same package. The enum avoids Optional wrapping and makes the "no element + no error = closed" case explicit rather than relying on `(nil, nil)` sentinel.

**Fix C — Consuming extraction from State.Sender (addresses Finding #3)**

Replace `let element: Element` with consuming extraction when the sender is popped.

```swift
// Option 1: Split Sender into metadata + element for independent consumption
@usableFromInline
struct SuspendedSend: Sendable {
    @usableFromInline let id: UInt64
    @usableFromInline let continuation: Send.Continuation
    @usableFromInline let element: Element
}

// In popNextSender, after take from Deque, the SuspendedSend is consumed:
// let element = sender.element  // still a copy from let field
```

This is harder to fix because the sender struct contains both the element (needed by receiver) and the continuation (needed to resume the sender). Both are needed after popping but by different consumers. The current design reads `.element` and `.continuation` independently.

A true zero-copy fix would require either:
- Making Sender `~Copyable` and providing `consuming` decomposition (but Sender is stored in `Deque<Sender>` which works with ~Copyable, though the `Sendable` conformance on Sender would need `@unchecked`)
- Separating element and continuation into parallel queues (increases complexity, risk of desynchronization)

**Risk**: High. Structural change to state machine internals. **DEFERRED** until profiling shows this copy is material.

**Fix D — Broadcast single-subscriber fast path (addresses Finding #5)**

When only one subscriber is waiting, deliver directly without the `toResume` array.

```swift
// In Broadcast.send():
if wakeIds.count == 1 {
    // Single subscriber — deliver directly, skip array
    let id = wakeIds[0]
    if var subscriber = state.subscribers[id] {
        if let cont = subscriber.continuation {
            subscriber.cursor = index + 1
            subscriber.continuation = nil
            state.subscribers[id] = subscriber
            // Return single pair, not array
            return [(cont, element)]  // or use a dedicated single-vs-many return
        }
    }
}
```

**Risk**: Low, but marginal benefit. The array allocation for `toResume` is already O(waking) not O(total) after the prior performance audit fix. For the common single-subscriber case, the array is size 1, which the small-buffer optimization may inline. **DEFERRED** unless profiling shows array allocation is hot.

**Fix E — `consuming` on state machine send methods (addresses Finding #6)**

```swift
// Async.Channel.Bounded.State.swift:178
mutating func trySend(_ element: consuming Element) -> Send.Action { ... }

// Async.Channel.Unbounded.State.swift:94
mutating func send(_ element: consuming Element) -> Send.Action { ... }
```

**Risk**: Low. The element is always either stored (buffer/sender) or placed in an Action enum. Adding `consuming` makes the ownership transfer explicit. However, on the paths where the element enters an Action enum associated value, the element is already passed by value, so the compiler should already optimize this. The benefit is documentation clarity and enabling future ~Copyable evolution.

### Summary

9 findings: 0 critical, 2 high, 4 medium, 3 low (including 2 false positives). **5 resolved**, 1 improved, 3 unchanged (1 open, 2 false positives).

**Resolved — Continuation copy elimination** (#1): `Async.Continuation.resume(returning:)` and `.Unsafe.resume(returning:)` now take `consuming` parameter, matching the stdlib `UnsafeContinuation.resume(returning: consuming sending T)` contract. Eliminates 1 copy per element delivery across all channel types.

**Resolved — Tri-state receive outcome → Signal + deliverySlot** (#2): Bounded and unbounded channels now use `Receive.Signal` enum (`.delivered` | `.closed` | `.cancelled`) for the continuation, with the element transferred via a persistent `Ownership.Slot<Element>` (deliverySlot) on Storage. This completely eliminates Optional wrapping, tuple construction, and element transport through the continuation type.

**Resolved — Sender.element let-field copy** (#3): The ~Copyable restructure (`6f04280f`) replaced `let element: Element` with `let slot: Ownership.Slot<Element>` in the Sender struct. Reading `sender.slot` copies a class reference (trivial); `slot.take(__unchecked:)` atomically moves the element via CAS + pointer move. The 1-copy-per-suspended-sender-delivery is eliminated.

**Improved — Action enum extraction** (#4): All fast-path switches now use `switch consume`, which forces destructive pattern matching for ~Copyable elements (guaranteed move). For Copyable elements, optimizer-dependent as before.

**Resolved — `consuming` on state machine sends** (#6): Now moot — state machine methods receive `Ownership.Slot<Element>` (Copyable reference) instead of `Element` directly.

**Core insight**: The entire element pipeline is now zero-copy for ~Copyable elements. The Deque layer uses `consuming` push and destructive take. The Slot-based staging adds ~100-140ns overhead per send (1 malloc/free + 4 atomics) as the cost of ~Copyable closure capture avoidance. The remaining considerations are:

1. **Action enum extraction** (Finding #4, IMPROVED): 0 copies for ~Copyable (forced by `consume`), optimizer-dependent for Copyable.
2. **Broadcast fan-out** (Finding #5, OPEN): inherent for N>1 subscribers. Out of scope for channel restructure.
3. **Slot-per-send overhead**: ~100-140ns per send. Necessary for ~Copyable; a Copyable-specialized fast path could eliminate it for the common case. Not a correctness issue.

**~Copyable Element**: Internal constraints fully prepared. 1 genuine stdlib blocker remains (`UnsafeContinuation<T>` implicit Copyable). See `Research/zero-copy-noncopyable-element-feasibility.md`.

**~Sendable Element**: Blocked by `Mutex<State: Sendable>` → `Deque<Element: Sendable>` chain. Requires radically different architecture. DEFERRED.

**Concurrency annotations**: All correct. `nonisolated(nonsending)` applied to all async channel functions (migration completed 2026-03-31).

---

## Compiler Bug Tracking — 2026-03-31

### CopyPropagation crash on `switch consume` of ~Copyable enums

| Field | Value |
|-------|-------|
| Severity | HIGH |
| Target | Async Channel Primitives (Bounded + Unbounded) |
| Trigger | `swift build -c release --target "Async Channel Primitives"` |
| Crash | CopyPropagation `initializeConsumingUse` in `isCompatibleDefUse` — ownership verification failure on `switch consume` of ~Copyable Action enums |
| Root cause | **swiftlang/swift#85743** — SILGen emits `load [take]` instead of `load [trivial]` for trivial tuple elements in consuming switch on address-only enums. CopyPropagation detects this in non-assertion builds. |
| Affected Swift | 6.3 (Xcode). **Fixed** in Swift 6.4-dev (commit `e93ea1db266`, PR #85745, merged 2025-12-04). |
| Upstream issue | **swiftlang/swift#85743** (CLOSED) |
| Status | **WORKAROUND** (`59701830`) — remove when Xcode ships Swift 6.4+ |

**Correction (2026-03-31 follow-up investigation)**: The prior note stated this
was distinct from #85743. That was based on inability to test on 6.4-dev
(DeinitDevirtualizer blocked the superrepo build). A standalone reproducer
matching the exact `Receive.Action` field layout (`Element: ~Copyable` +
`Optional<Cont>` trivial + `Optional<Array<Cont>>` non-trivial) confirms:
- Xcode 6.3 + `-sil-verify-all`: crashes with `load [take] $*Optional<Cont>`
- 6.4-dev + `-sil-verify-all`: passes clean (exit 0)

The CopyPropagation manifestation is the same root cause detected later in the
pipeline: assertion builds catch it at SILGen; non-assertion builds (Xcode) let
the bad SIL through until CopyPropagation's ownership canonicalization detects it.

See `/Users/coen/Developer/HANDOFF-copypropagation-noncopyable-enum.md` for full
investigation record.

**Workaround applied** (commit `59701830`):
- `@_optimize(none)` on 4 outer async/sync functions (receive, send, next, immediate)
- Slow-path action handling extracted to `Storage.handleReceive` / `Storage.handleSend` static functions with `@_optimize(none)` (3 handlers)
- 7 total `@_optimize(none)` annotations across 6 files

**Affected functions** (Bounded + Unbounded, all workaround-annotated):
- `Bounded.Receiver.receive()` — async, fast + slow path
- `Bounded.Receiver.Receive.immediate()` — sync
- `Bounded.Elements.Iterator.next()` — async, fast + slow path
- `Bounded.Sender.send(_:)` — async, fast + slow path
- `Bounded.Sender.Send.immediate(_:)` — sync
- `Unbounded.Receiver.receive()` — async, fast + slow path
- `Unbounded.Elements.Iterator.next()` — async, fast + slow path
- `Unbounded.Sender.send(_:)` — sync

**Benchmark impact**: Geometric mean 1.04x vs previous release runs (negligible). Two cancellation benchmarks regressed 0.5–0.8x due to `@_optimize(none)` on the receive path. All throughput/contention/lifecycle benchmarks within 10%.

**When to remove**: When Xcode ships Swift 6.4+ (which includes `e93ea1db266`). Remove all 7 `@_optimize(none)` annotations — search for "CopyPropagation" in WORKAROUND comments.

### nonisolated(nonsending) migration — 2026-03-31

| Field | Value |
|-------|-------|
| Severity | LOW (API modernization) |
| Status | **RESOLVED** |

Migrated 4 channel functions from `isolation: isolated (any Actor)? = #isolation` to `nonisolated(nonsending)`:
- `Bounded.Receiver.receive()`, `Bounded.Elements.Iterator.next()`
- `Unbounded.Receiver.receive()`, `Unbounded.Elements.Iterator.next()`

Aligns with existing `nonisolated(nonsending)` usage on `Sender.send(_:)` (already migrated). `Async.Broadcast` subscriber not yet migrated (separate scope).

### Separate blocker: DeinitDevirtualizer on 6.4-dev

Not in this package — affects `Buffer_Primitives_Core` (`Buffer<UInt8>.Unbounded._storage` setter). Blocks the full superrepo release build on 6.4-dev. See `/Users/coen/Developer/swift-primitives/swift-buffer-primitives/HANDOFF-deinit-devirtualizer-crash.md` and `/Users/coen/Developer/HANDOFF-deinit-devirtualizer-upstream.md`.
