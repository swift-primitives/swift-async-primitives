# Investigation: Channel.Bounded.Receiver release-mode CopyPropagation crash

> To investigate: read this file for full context. Use the `/issue-investigation` skill.
> The parent conversation's work (Mutex implementation + modularization) is committed.

## Issue

`swift build -c release --target "Async Channel Primitives"` crashes in SIL pass CopyPropagation (#600) on `Async.Channel.Bounded.Receiver.receive(isolation:)` at `Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.swift:69`.

Error signature:
```
Have operand with incompatible ownership?!
Value:   load [take] %34 : $*Optional<Async.Continuation<Optional<Async._ChannelError>>.Unsafe>
User:   switch_enum ... forwarding: @none
Conv: owned / Constraint: Kind:none
```

Root cause: SILGen's `emitDestructiveCaseBlocks()` uses `B.createLoad(...Take)` unconditionally instead of `TypeLowering::emitLoad()`. Triggers on generic ~Copyable enum + tuple payload with trivial field + consuming switch. **Already fixed in Swift 6.4-dev** (swiftlang/swift#85743, commit `e93ea1db266` by Benjamin Levine).

## Parent Context

Mutex implementation and full modularization of async-primitives just completed. Channel depends on the new `Async Mutex Primitives` target. The crash is pre-existing — confirmed identical with old `Synchronization.Mutex` typealias.

## Relevant Files

- `Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.swift:69` — crash site
- `Sources/Async Channel Primitives/Async.Channel.Bounded.Sender.swift` — may have `@_optimize(none)` workarounds
- `Sources/Async Channel Primitives/Async.Channel.Unbounded.Receiver.swift` — may also be affected
- `Research/audit.md` — tracks deferred workaround removal

## Do Not Touch

No uncommitted changes — working tree is clean.

## Scope

1. Verify which Channel functions currently have `@_optimize(none)` workarounds
2. Verify the crash reproduces ONLY in Channel (all other targets pass release — confirmed)
3. Document the minimum Swift version that includes the fix
4. Ensure `Research/audit.md` tracks removal of `@_optimize(none)` once Xcode ships 6.4+

Do NOT attempt a compiler fix or deep SIL analysis — the fix is already upstream.

## Findings

Investigation date: 2026-03-31.

### 1. `@_optimize(none)` Workarounds: None

Zero `@_optimize(none)` annotations exist anywhere in `swift-async-primitives`. The Channel target is unguarded — it simply cannot be built in release mode on Swift 6.3. No workaround has been applied.

### 2. Crash Isolation: Confirmed — Channel Only

All non-Channel targets pass `swift build -c release` on Swift 6.3 (Xcode):

| Target | Release build |
|--------|--------------|
| Async Primitives Core | Pass |
| Async Mutex Primitives | Pass |
| Async Bridge Primitives | Pass |
| Async Promise Primitives | Pass |
| Async Publication Primitives | Pass |
| Async Barrier Primitives | Pass |
| Async Completion Primitives | Pass |
| Async Broadcast Primitives | Pass |
| Async Timer Primitives | Pass |
| Async Waiter Primitives | Pass |
| **Async Channel Primitives** | **Crash — CopyPropagation pass #600** |

Crash site: `receive(isolation:)` at `Async.Channel.Bounded.Receiver.swift:69`. The function consumes `Receive.Action` (a generic `~Copyable` enum) whose `.returnElement` case has a 3-field tuple payload including `Send.Continuation?` and `Deque<Send.Continuation>?` — Optional pointer types that are trivially loadable. SILGen emits `load [take]` unconditionally for all tuple elements including these trivial fields; CopyPropagation's ownership verifier rejects the `owned` load forwarded into a `@none` `switch_enum`.

Other functions with the same pattern (consuming switch on `~Copyable` enum with tuple payloads) are likely also affected but the compiler aborts on the first failure:
- `Bounded.Receiver.receive(isolation:)` — confirmed crash site
- `Bounded.Elements.Iterator.next(isolation:)` — same `switch consume fastAction` on `Receive.Action`
- `Bounded.Receive.immediate()` — same pattern
- `Bounded.Sender.send(_:)` — `switch consume decision` on `Send.Decision`
- `Bounded.Send.immediate(_:)` — same pattern

Unbounded variants use `Receive.Step` which has single-field payloads (`.val(Element)`, not tuples), so they may not trigger the bug.

### 3. Minimum Swift Version

| Datum | Value |
|-------|-------|
| Fix commit | `e93ea1db266` ("[SILGen] Fix load ownership for trivial tuple elements in consuming switch") |
| Author | Benjamin Levine |
| Authored | 2025-11-30 |
| Merged to `main` | 2025-12-04 (PR #85745) |
| In `release/6.3`? | **No** — `git merge-base --is-ancestor` returns false |
| In dev toolchain? | **Yes** — 2026-03-16 snapshot post-dates merge by 3+ months |
| Minimum release | **Swift 6.4** (first release from `main` after the fix) |

**Dev toolchain verification**: Full SwiftPM build blocked by a separate `Bit_Field_Primitives` IRGen regression (`hasErrorResult()` in Types.h:5369) in the 2026-03-16 snapshot — `swift-bit-primitives` is in the transitive dependency graph and crashes before Channel compiles. However, a standalone reproducer (`/tmp/copyprop-repro4.swift`) that isolates the exact bug pattern (async + typed throws + consuming switch on generic `~Copyable` enum with trivial Optional tuple fields, `@inlinable` + `@usableFromInline`) **crashes on Swift 6.3 and passes on Swift 6.4-dev**, confirming the fix is present and effective.

### 4. Audit Tracking

Entry added to `Research/audit.md` under new "Compiler Bug Tracking" section.

### Recommendation

Apply `@_optimize(none)` to the 5 affected Bounded Channel functions (listed above) with the standard workaround annotation:

```swift
// WORKAROUND: SILGen emits load [take] for trivial tuple elements in consuming switch
// WHY: swiftlang/swift#85743 — emitDestructiveCaseBlocks uses createLoad(...Take)
//      instead of TypeLowering::emitLoad()
// TRACKING: e93ea1db266 (merged to main 2025-12-04, PR #85745)
// WHEN TO REMOVE: Swift 6.4+ (Xcode ships 6.4)
@_optimize(none)
```

This restores release-mode buildability for the Channel target on Swift 6.3.
