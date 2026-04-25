# Semantics

@Metadata {
    @TitleHeading("Article")
}

Per-primitive contracts for cancellation observation, ordering, backpressure,
and fairness across the coordination primitives.

## Overview

This article tabulates the four semantic properties a reader should be able to
reason about when choosing between primitives or composing them in
production-quality code:

- **Cancellation observation** — what happens when the surrounding Task is
  cancelled during an operation on this primitive? What does the primitive
  throw, return, or leave in progress?
- **Ordering** — in what order are operations observed by callers? FIFO /
  per-sender-FIFO / unordered / single-value / N/A.
- **Backpressure** — how does the primitive handle a mismatch between
  producer and consumer rate? Bounded / unbounded / capacity-limited /
  overwrite / drop / N/A.
- **Fairness** — under contention, is admission ordered (FIFO), arbitrary,
  or undefined? Where relevant, is starvation possible?

The table below is the authoritative per-primitive summary. Cells marked
`gap` are known pre-1.0 work — the property is not yet specified and will
be documented before v1.0.

## Table

| Primitive | Cancellation observation | Ordering | Backpressure | Fairness |
|---|---|---|---|---|
| ``Async/Barrier`` | **Non-observing by signature** with two cases. Cancelled mid-await: cancelled party's continuation stays in waiter list; when barrier releases, the cancelled task resumes alongside the others (pinned by `arrive() does not observe Task cancellation mid-await`). Cancelled before `arrive()` is called: party never increments the arrival count → barrier never releases → other parties wait forever. Callers MUST guarantee each party calls `arrive()` exactly once; the barrier exposes no cancellation-release path | N/A (no ordering — all parties released atomically when party-count reached) | N/A (fixed party count at init; one-shot) | Release is simultaneous to all waiters; resume order among waiters after release is **undefined** |
| ``Async/Bridge`` | **Non-observing by signature.** `next()` is `async -> Element?` (not throws); a cancelled consumer Task suspended in `next()` continues to suspend until `push(_:)` or `finish()` signals, then resumes with the element (or `nil`). Termination is the producer's responsibility. Pinned by `Async.Bridge Tests.swift` | FIFO (single-consumer; Deque-backed internal buffer pushes to back, pops from front) | **None** (unbounded internal buffer via Deque) | Single-consumer invariant; no multi-reader fairness question |
| ``Async/Broadcast`` | `next()` throws ``Async/Broadcast/Error/cancelled``; token-matching cancellation per §5.3 (exactly-once continuation resumption) | Per-subscriber FIFO for delivered items. Across subscribers on a single `send(_:)`: **subscription-order resume** (oldest subscription resumed first; `state.subscribers` is `Dictionary<…>.Ordered`). Resume-call order differs from task-completion order, which is scheduler-determined | **Replay-window bounded** (`bufferCapacity`, default 64). Slow subscribers that fall behind the replay window **silently drop** intermediate events | Subscription-order wakeup signal; observable completion is scheduler-determined |
| ``Async/Broadcast/Subscription`` | Inherits Broadcast's cancellation semantics via its `AsyncSequence` iterator; `cancel()` is idempotent and triggers `.finished` resumption for any pending `next()` | Per-subscription cursor (independent across subscriptions) | Inherits Broadcast's replay-window | Inherits Broadcast |
| ``Async/Channel/Bounded`` | `send(_:)` / `receive()` throw ``Async/Channel/Error/cancelled``; closed-channel path: `.closed` (send) or `nil` return (receive). Auto-close when last `Sender` drops propagates through active receivers | `gap` — per-sender FIFO is guaranteed by the internal queue mutex; **multi-sender interleaving ordering** (whether two concurrent `send(_:)` calls on two distinct Senders observe a global order or only per-sender order) is not yet specified | Capacity-bounded; `send(_:)` suspends when buffer full (backpressure) | `gap` — sender wakeup order under contention is not yet specified; internal queue mutex serializes so arrival-order semantics are a reasonable assumption but undocumented |
| ``Async/Channel/Unbounded`` | `receive()` throws ``Async/Channel/Error/cancelled``; closed-channel path: `nil` return after drain; Sender side is non-throwing (sync send). Single-suspended-receiver invariant: concurrent suspended `receive()` calls trap (precondition) | FIFO | **None** (unbounded internal buffer) | Single-receiver invariant; no fairness question on the consumer side |
| ``Async/Completion`` | `cancel()` transitions `pending \| running → cancelled` via CAS; exactly-once resumption guarantee. Throws ``Async/Completion/Transition/Error/alreadyDone`` if the state is already terminal when a second transition is attempted | N/A (single-value terminal result) | N/A (single-value) | CAS race — the first transition wins deterministically; others throw `.alreadyDone` |
| ``Async/Mutex`` | — (synchronous; not cancellation-observing by design. `withLock { }` does not test `Task.isCancelled`) | N/A (single-lock acquire) | N/A (binary lock) | **Unfair** — `os_unfair_lock` is unfair by default on Darwin; on Linux/Windows the typealias to `Synchronization.Mutex` inherits that primitive's fairness (stdlib-defined). For FIFO admission, compose ``Async/Semaphore`` (FIFO) over the protected state rather than using Mutex directly |
| ``Async/Promise`` | **Non-observing by signature.** `value()` is `async -> Value` (not throws); a cancelled Task awaiting `value()` continues to suspend until `fulfill(_:)` is invoked, then resumes with the fulfilled value. Callers who need cancellation must compose externally (e.g. inside `withTaskCancellationHandler`). Pinned by `Async.Core Tests.swift` `value() does not observe Task cancellation` | N/A (single-value; all current and future awaiters observe the same fulfilled value) | N/A (single-value) | All waiters resume with the same value when `fulfill(_:)` wins the single-fulfillment race; no fairness question |
| ``Async/Publication`` | N/A — designed for cancellation-handler racing (`take()` is atomic winner-takes-all; losers receive `nil`, no trap). The primitive IS part of the cancellation-observation mechanism in consuming APIs | Latest-write-wins on `publish(_:)` (overwrite-on-publish). `take()` is atomic take-and-clear | N/A (overwrite-on-publish; not a queue) | Winner-takes-all: exactly one racing caller wins `take()`, others see `nil` |
| ``Async/Semaphore`` | `wait()` throws ``Async/Semaphore/Error/cancelled``; `wait(timeout:)` adds `.timeout`; `shutdown()` wakes all waiters with `.shutdown`. `withPermit(_:)` returns `Either<Async.Semaphore.Error, E>` — `.left` is an acquisition failure, `.right` is a body failure | FIFO (waiters acquire in arrival order) | Capacity-bounded (acts as concurrency limit); `wait()` suspends when capacity saturated | **FIFO** |

Building-block namespaces are deliberately excluded from the table: ``Async/Timer``
and ``Async/Waiter`` are namespaces holding data-structure primitives
(``Async/Timer/Wheel``, ``Async/Waiter/Queue``, ``Async/Waiter/Flag``, etc.) used
to compose coordination, not coordination primitives themselves.

## Gap inventory

The `gap` cells above are the authoritative list of semantic properties to
specify before v1.0:

4. ``Async/Channel/Bounded`` multi-sender interleaving ordering — whether
   the internal queue mutex provides arrival-order semantics across distinct
   Senders, or only per-sender FIFO.
5. ``Async/Channel/Bounded`` sender-wakeup fairness under contention —
   whether waiters on `send(_:)` drain in arrival order.

Each gap is a small documentation addition backed by either an existing
test, a small new test, or (where the current behavior is accidental) a
deliberate design call followed by a documentation + test pair.

## Cancellation-error naming consistency

Per the per-primitive cancellation-error-type question (tracked as
`Research/forums-review-triage-2026-04-24.md` Q4 / Open Question #2):

- ``Async/Semaphore/Error`` uses `.cancelled` — typealiased to ``Async/Lifecycle/Error``
- ``Async/Broadcast/Error`` uses `.cancelled` — per-primitive enum
- ``Async/Channel/Error`` uses `.cancelled` — per-primitive enum
- ``Async/Completion/Error`` uses `.cancellation` (noun) — per-primitive enum, the lone outlier
- ``Async/Lifecycle/Error`` is non-generic with cases `shutdown` / `cancelled` / `timeout`

The principle: typealias a per-primitive error to ``Async/Lifecycle/Error``
ONLY when all three of `.shutdown`, `.cancelled`, and `.timeout` apply to
the primitive. Semaphore satisfies this; Broadcast, Channel, and Completion
do not (Broadcast has no shutdown or timeout; Channel mixes `.cancelled`
with `.closed`/`.full`/`.empty` domain cases; Completion has no shutdown).
Force-fitting them through the wider type just for typealias uniformity
introduces phantom cases that never fire and obscures each primitive's
actual semantic surface.

The residual `.cancellation` (noun) vs `.cancelled` (past participle)
inconsistency in ``Async/Completion/Error`` is a known pre-1.0
normalization target. Resolving it does not require lifting Completion
through ``Async/Lifecycle/Error`` — a simple in-place case rename
suffices.

## Composition

Two composition patterns worth calling out explicitly, since they weren't
implied by the per-primitive table:

- **FIFO admission over mutexed state**: compose ``Async/Semaphore`` (FIFO)
  around the region holding the ``Async/Mutex`` if fair admission matters.
  Mutex does not provide it; Semaphore does.
- **Cancellation-handler racing**: use ``Async/Publication`` inside a
  `withTaskCancellationHandler` block to safely race the operation closure
  and the `onCancel` handler for claim-ownership of a single resource.
  `take()` is winner-takes-all and trap-free on the losing side.

## Source of truth

This article is derived from per-primitive docstrings as of 2026-04-24. When
a primitive's behavior is clarified (documented or tested) into a `gap` cell,
update both the docstring at the source and this table in the same commit
so the two remain in sync. A `gap` cell that has been filled in the
docstring without this article being updated is a documentation drift;
treat it as a defect.
