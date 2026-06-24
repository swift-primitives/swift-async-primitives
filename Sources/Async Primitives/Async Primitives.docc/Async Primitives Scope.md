# Async Primitives Scope

The identity surface of `swift-async-primitives`, and what is deliberately out of it.

## Identity

`swift-async-primitives` provides **raw async coordination primitives a layer below
`AsyncSequence`** — the policy-free building blocks for handing values and control between
concurrent tasks. It owns the continuation/callback bridge from non-`async` code, mutual
exclusion, lifecycle/shutdown state, and the coordination structures composed on a
mutex + waiter substrate (channel, broadcast, semaphore, barrier, promise, publication,
completion). Every type is a policy-free building block with `~Copyable` element support,
typed throws, and observable cancellation; higher-level scheduling and structured-concurrency
conveniences are composed above this layer, not here.

## Core targets

Per [MOD-017]/[MOD-031], the root namespace + foundational declarations live in the singular
`Async Primitive`, and each sub-namespace `Async.{X}` is its own target:

- `Async Primitive` — the `Async` namespace root and foundational, stdlib-only declarations
  (zero external dependencies per [MOD-017]).
- `Async Callback Primitives` — `Async.Callback`, an isolation-preserving deferred value.
- `Async Continuation Primitives` — `Async.Continuation` (and `Async.Continuation.Unsafe`),
  the unified continuation over `CheckedContinuation`/callback.
- `Async Lifecycle Primitives` — `Async.Lifecycle` open→closing→closed state machine and
  `Async.Lifecycle.Error`.
- `Async Precedence Primitives` — `Async.Precedence`, competing-condition resolution policy.
- `Async Mutex Primitives` — `Async.Mutex`, the async-aware mutual-exclusion primitive.
- `Async Waiter Primitives` — `Async.Waiter`, the suspension/resumption substrate.
- `Async Bridge Primitives` — `Async.Bridge`, sync→async handoff.
- `Async Promise Primitives` — `Async.Promise` / `Async.Gate`.
- `Async Publication Primitives` — `Async.Publication`.
- `Async Barrier Primitives` — `Async.Barrier`.
- `Async Completion Primitives` — `Async.Completion`.
- `Async Channel Primitives` — `Async.Channel` (`Bounded` / `Unbounded`).
- `Async Broadcast Primitives` — `Async.Broadcast`.
- `Async Semaphore Primitives` — `Async.Semaphore`.

## Out of scope

These compose with the package but lie OUTSIDE its identity surface:

- **Time wheels / timer scheduling**: removed 2026-06-24 — the prior `Async.Timer.Wheel` rode the
  archived `swift-buffer-arena-primitives`, had no consumers, and its scheduler was never
  implemented. Recoverable from git history; a future time-wheel would ride `Storage.Generational`.
- **Task/job scheduling and executors**: → `swift-executor-primitives`.
- **OS threads and kernel-level mutex** (`Kernel.Thread.Mutex`): → `swift-thread-primitives`
  (reached only through the `canImport` portability fallback in `Async.Mutex`).
- **Clocks, durations, deadlines**: → `swift-time-primitives` / `swift-clock-primitives`.
- **Underlying data structures** (queues, deques, ring/linear buffers, columns, dictionaries,
  hash tables): → their own primitive packages — consumed here, never owned.
- **`AsyncSequence` conformances and structured-concurrency conveniences**: → a composing
  layer above (foundations).

## Evaluation rule

Sub-target additions are evaluated against this scope. If a proposed addition is OUT of scope,
it extracts to a sibling package, not into this one.
