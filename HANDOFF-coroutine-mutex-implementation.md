# Handoff: Implement Coroutine-Capable Struct Mutex in async-primitives

> **STATUS: COMPLETE** (2026-03-31). Committed as `726dd02`.

## Goal

Replace the `Synchronization.Mutex` typealias in `Async.Mutex` with a purpose-built struct Mutex that provides both closure-based (`withLock`) and coroutine-based (`locked`) access. The coroutine accessor eliminates closures, Optional wrappers, and `.take()!` for ~Copyable value transfer — enabling `_state.locked.value.buffer.push(consume element, to: .back)`.

## Current State

**DONE.** Struct Mutex implemented on Darwin with `@_rawLayout` + `os_unfair_lock`. Full modularization completed — `Async Mutex Primitives` is an independent target. All 10 non-Channel targets pass release. Channel crash is pre-existing (swiftlang/swift#85743, fixed in 6.4-dev). Bridge.push() stays with `withLock` (transactional). Channel state machines stay with closures (transactional).

## Key Decisions

- **nonmutating _modify** on Locked view — enables `_read`-only on Mutex (works with `let`), mutation through raw pointer.
- **~Copyable only, not ~Escapable** on Locked — `~Escapable` lifetime checker rejects views on class stored properties. `_read` scope prevents escape.
- **Two-level @_rawLayout** (Memory.Inline pattern) — inner `_ValueRaw`/`_LockRaw` structs. Pointer via `withUnsafePointer(to:)`.
- **`let` binding** — avoids dynamic exclusivity concerns. `borrowing func withLock` + `_read`-only `locked` both work with `let`.
- **`withLock` coexists** — backward compatibility for existing closure-based call sites.

## Dead Ends

- **Synchronization.Mutex extension** — yield can't appear in closures. `handle._lock()`/`_unlock()` internal.
- **`private var` + `mutating _modify`** — dynamic exclusivity concerns for concurrent access.
- **`~Escapable` on Locked** — lifetime checker rejects on class stored properties.

## Changed Files

No implementation changes yet. Existing committed artifacts:
- `Sources/Async Primitives Core/Async.Mutex.swift` — typealias to replace
- `Sources/Async Primitives Core/Async.Mutex+Ownership.swift` — closure extensions (backward compat)
- `Sources/Async Primitives Core/Async.Bridge.swift` — uses `withLock(consuming:)`, migrate to `locked`

## Next Steps

1. Add `RawLayout` experimental feature to `Package.swift`
2. Implement `Async.Mutex` struct in `Async.Mutex.swift` (replace Synchronization typealias on non-embedded path). Copy architecture from `Experiments/mutex-coroutine-rawlayout/Sources/main.swift`
3. Verify `Async.Mutex+Deque.swift` compiles against new Mutex
4. Migrate `Bridge.push()` to `locked` accessor
5. Build all modules (Core, Channel, Broadcast, Timer, Waiter) — `swift build`
6. Test release mode — `swift build -c release`
7. Evaluate Channel migration (transactional state machine may prefer closure path)

## Constraints

- **@_rawLayout deinit bug** (#86652): test `_ValueRaw` deinit in release carefully.
- **Embedded path** (`#else`): keep no-op class Mutex with `withLock` only.
- **Kernel path** (`canImport(Kernel_Primitives)`): `Kernel.Thread.Mutex.Value` doesn't exist. Leave as-is.
- **`Async.Mutex+Ownership.swift`**: keep for Channel code using closure patterns.
- **Research**: `swift-institute/Research/noncopyable-ownership-transfer-patterns.md` and `noncopyable-ergonomics-compiler-state.md` document the full investigation.
