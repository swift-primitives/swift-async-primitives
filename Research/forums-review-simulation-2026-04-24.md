---
package: swift-async-primitives
path: /Users/coen/Developer/swift-primitives/swift-async-primitives
simulated_date: 2026-04-24
predicted_category: related-projects
corpus_state: full (602 threads, 25,428 posts, 11,674 substantive)
skill_version: v1.2 (FREVIEW-001..017, venue-stratified + era-corrected)
venue_base_rates: stratified:related-projects (n=224)
era_correction: swift6-era (per-angle multipliers applied)
terminal_posture: not detected
seed: 3
archetypes_used:
  - "post 2  — c1 general-purpose technical reviewer"
  - "post 3  — c9 long-form deep-analysis essay reviewer"
  - "post 4  — c8 SwiftPM / build-tooling / modularity reviewer"
  - "post 5  — c10 heavy-quoting long-form authoritative reviewer"
  - "post 6  — c3 closure / expression / syntax technical reviewer"
  - "post 7  — c4 constructive Evolution-process reviewer"
  - "post 8  — c2 ~Copyable / Sendable / protocol-shape reviewer"
  - "post 9  — c7 init / deinit / lifecycle reviewer"
  - "post 10 — c6 Core-Team-aware process voice"
  - "post 11 — c5 pointed -1 reviewer"
note: INTERNAL simulation artifact. Handles anonymized (@reviewer-N). Do NOT post anywhere. Regenerate via FREVIEW-011 on corpus refresh.
---

# [Simulated] Introducing: Async Primitives — 13 coordination primitives for Swift concurrency, Swift-Embedded-compatible

<!-- archetype: OP (author voice) -->

### Post 1 — @op

Hi all,

I've tagged a first release of `swift-async-primitives` — a small-grain L1 package in the Swift Institute primitives ecosystem that declares 13 coordination primitives under a single `Async` namespace, shipped as 14 separate library products.

The coordination surface:

```
Async.Channel.Bounded<Element: ~Copyable>      - single-producer / single-consumer bounded channel (MPSC via Sender clone)
Async.Broadcast<Element>                        - single-producer / multi-consumer broadcast
Async.Barrier                                   - party-count barrier
Async.Semaphore                                 - counting semaphore
Async.Mutex<State>                              - value-owning mutex (Darwin-gated today; see below)
Async.Waiter                                    - one-shot suspension primitive
Async.Promise<Success, Failure: Error>          - single-value completion
Async.Completion                                - void completion
Async.Publication                               - fan-out publication
Async.Bridge                                    - sync-to-async handoff
Async.Timer                                     - async delay with deadline
Async.Semaphore.Token                           - RAII-style acquired-permit handle
Async.Broadcast.Subscription                    - per-subscriber cursor
```

The package ships 15 targets / 14 public products so consumers can pull exactly the primitives they need. `Async Primitives Core` (embedded-compatible) is the dependency-free namespace root; `Async Primitives` is the convenience umbrella. The coordination primitives that require task-suspension are gated with `#if !hasFeature(Embedded)` — they're declared but absent on embedded deployments.

Highlights of the design posture:

1. **`~Copyable` element support throughout**. 157 `~Copyable` type declarations across the package. Channels, broadcast, promise, completion all carry `<Element: ~Copyable>` and thread ownership through `borrowing` / `consuming` parameters.
2. **Typed throws on every fallible surface**. 42 `throws(E)` declarations across the package. Cancellation errors are concrete types (`Async.Channel.Error.cancelled`, `Async.Broadcast.Error.cancelled`, etc.), not `any Error`.
3. **Cancellation-safety by design**. Every `async` operation specifies its cancellation observation semantics in its docstring; cancellation tokens are advance-or-resume consistent with SE-0304.
4. **Mutex uses `_read` coroutine**. `Async.Mutex<State>` exposes `locked` as a coroutine-based accessor on top of `os_unfair_lock`, so `~Copyable` state can be mutated without Optional-wrapping or `.take()!` shenanigans.

What I'm looking for: feedback on target granularity (14 products is a lot), on how the cancellation-safety claims should be formalised, on the Darwin-only Mutex situation, and on how this package positions relative to `swift-async-algorithms`.

Code is at `Sources/` (organised one product per directory). Design notes for the channel and broadcast primitives are in `Research/`.

---

### Post 2 — @reviewer-c1

<!-- archetype: The general-purpose technical reviewer (canonical c1) — target: concurrency, evolution-process, type-system — opener: question — closer: question-to-author -->

Read through the top-level README and the channel code. One thing I want to understand better before I form a stance.

`Async.Channel.Bounded.Sender` at `Sources/Async Channel Primitives/Async.Channel.Bounded.Sender.swift:45` is declared as `public struct Sender: Sendable` — so it's `Copyable & Sendable`. The element type is `<Element: ~Copyable>`, and the docstring says "Multiple senders can share the same channel by copying the handle (each copy shares the underlying storage)." So sender-ARC increments the underlying storage refcount, and "auto-close on last drop" fires when the last Sender handle is released.

Question: does this work under `sending` semantics in async contexts? If I pass a `Sender` to a child task in `withTaskGroup`, Swift 6 isolation will insist the passed-in value is `sending`. A `Sendable` struct passed across an isolation boundary is OK, but for the copy-to-increment semantic you're describing, I want to verify that the sender's copy-on-pass inside a task group is the same handle (shared storage) rather than a fresh value. Is there a test that exercises `Task { channel.sender.send(...) }` paths and confirms the auto-close fires when all child tasks complete?

Related: the `Async.Channel.Bounded.Receiver.Receive` operation at `Async.Channel.Bounded.Receiver.Receive.swift:33` is called `immediate`. I'd have expected `receiveImmediate()` or `.receive(.immediate)` on the receiver — `immediate` as a method name on a receiver reads a bit like a property. Is there a design doc for the receive-family naming?

---

### Post 3 — @reviewer-c9

<!-- archetype: The long-form deep-analysis essay reviewer (canonical c9) — target: concurrency, evolution-process, type-system — opener: thanks — closer: question-to-author -->

Thanks for shipping this, and particularly for writing the cancellation-safety claims into docstrings rather than leaving them implied. Reading through `Async.Broadcast` and the subscription machinery, I want to work through a few concurrency-semantic questions in detail — some of these may already be answered in the Research/ notes and I just haven't found them, but they're the ones I'd need settled before using this in anything load-bearing.

**Broadcast linearizability.** The docstring for `Async.Broadcast` at `Sources/Async Broadcast Primitives/Async.Broadcast.swift` says: "Cursor advances when element is delivered (resumed). If subscriber is cancelled after resumption, it may not observe that element." That's a specific ordering claim — the cursor commits to advance before observer code runs, so cancellation *after* the continuation resumes can drop an already-delivered item on the floor. Two questions: (a) is there a test suite that exercises the cancellation-during-resume window specifically? And (b) does this generalise to the buffered replay case? The docstring also says "Slow subscribers may miss events if they fall behind the replay window" — so a subscriber that has fallen behind the `buffer.limit=64` window silently drops earlier elements. That's a delivery-semantics choice I can live with, but I'd want it called out in the README (it currently isn't), not just in the per-file docstring. New users will reach for broadcast expecting durable delivery.

**Channel multi-sender ordering.** Per @reviewer-c1 above, Sender is a clonable handle. If two `Task`s each hold a sender and call `send(_:)` concurrently, what's the delivery order to the receiver? The README doesn't state this. Best-case answer is "arrival order at the internal queue mutex", which is fine — but it should be documented, because the alternative answers (per-sender FIFO with interleaving between senders) are also defensible and downstream code will depend on which one ships.

**Barrier party-count commit.** `Async.Barrier.arrive()` at `Sources/Async Barrier Primitives/Async.Barrier.swift:95` — is the party count fixed at init, or can it grow? If a barrier is waiting for N arrivals and a task is cancelled before its arrival, does the barrier become un-releasable and deadlock the other waiters, or is there a release path for cancelled-before-arrival? This is the class of question that's easy to get wrong silently; Rust's `parking_lot` barrier, for comparison, offers a `wait_timeout` but not a cancellation-release path, and a cancellation-release path is arguably the more Swift-idiomatic shape. Worth documenting and testing either way.

**Promise fulfilment races.** `Async.Promise.Success.Failure.Error` — does `fulfil(success:)` win over `fulfil(failure:)` if they race, or is first-write-wins? Typical promise designs are either (a) first-write-wins with subsequent writes trapping, or (b) last-write-wins, or (c) the promise is single-write with a distinct `trySet` / `set` split. Both (a) and (c) are defensible; (b) is almost never what anyone wants. Can you say which one this is?

Ends on a broader framing: the package is advertising 13 coordination primitives, but the load-bearing semantic claims are per-primitive. A top-level "Semantics" DocC article that tabulates (cancellation observation / ordering / backpressure / fairness) per primitive would do a lot of work. Right now a reader has to open each docstring to triangulate — which is fine for a maintainer, opaque for a drive-by consumer.

Is a Semantics article on the roadmap?

---

### Post 4 — @reviewer-c8

<!-- archetype: The SwiftPM / build-tooling / modularity reviewer (canonical c8) — target: layering-modularity, build-tooling, evolution-process — opener: question — closer: question-to-author -->

Quick look at `Package.swift`.

15 targets, 14 library products, organised one product per coordination primitive. That's aggressive granularity — on one reading it's exactly right (consumers pull only what they use, no vestigial dependencies), on another it's overkill for a 109-file, 8KLOC package. Three concrete questions:

1. **Is the granularity a contract or an artifact?** If a consumer imports `Async_Barrier_Primitives` today and next version you merge it into `Async_Primitives_Core` for cohesion reasons, that's a breaking change for the consumer's import line. Declaring 14 products commits to that many module boundaries forever.

2. **Embedded gating posture.** The `#if !hasFeature(Embedded)` gates live at source-file level (e.g. top of `Async.Channel.Bounded.Sender.swift`), not in the manifest. On an embedded target, importing `Async_Channel_Primitives` succeeds but the module is empty. Is that the intended posture, or should the `Package.swift` declare `condition: .when(platforms: [...])` / a `swiftSettings` gate so embedded builds can't import these modules at all? The "type exists but is empty on embedded" shape is surprising.

3. **Umbrella vs variant imports.** `Async Primitives` is the umbrella; `Async Primitives Core` is the no-dep root. Which is the recommended import for a downstream consumer? Per the Institute's `[feedback_no_umbrella_imports]` policy (if I'm reading it right from sibling packages' conventions), consumers should import narrow variants. Does the README recommend `import Async_Barrier_Primitives` over `import Async_Primitives`? The README doesn't currently say.

---

### Post 5 — @reviewer-c10

<!-- archetype: The heavy-quoting long-form authoritative reviewer (canonical c10) — target: evolution-process, concurrency, type-system — opener: direct-stance — closer: question-to-author -->

Going to thread through the points above because they interact.

> [@reviewer-c1] does this work under `sending` semantics in async contexts?

Yes, and I'd add: the issue isn't `sending` at the boundary, it's the per-handle ARC increment inside the task. A `Sendable` struct passed into a child `Task` is fine, but if the inner body does `let s2 = sender` (local copy for use in a spawned `detach`), that's where the handle-copy-as-storage-refcount semantics need to hold. Worth making explicit in the Sender docstring: "Copying a `Sender` increments the channel's sender-handle refcount; the channel auto-closes when all Sender copies — across all tasks — are released." Current text at `Async.Channel.Bounded.Sender.swift:45` talks about "each copy shares the underlying storage" which understates the ARC mechanics.

> [@reviewer-c8] Is the granularity a contract or an artifact?

This is the single biggest post-1.0 commitment in the package. I'd argue that declaring 14 products is fine IF the semantics are that each product is an independently-SemVer-ed module. It's NOT fine if the intent is "one superrepo, one version, 14 modules that move together" — in that case, the products mislead. From `Package.swift` alone I can't tell which you mean. Pick one and write it down.

> [@reviewer-c9] A top-level "Semantics" DocC article that tabulates...

Strongly seconded. And I'd make the table specifically this shape:

| Primitive | Cancellation observation | Ordering | Backpressure | Fairness |
|---|---|---|---|---|
| Channel.Bounded | ? | per-sender FIFO? | capacity-bounded | ? |
| Broadcast | delivered-or-dropped | per-subscriber FIFO | replay-window=64 | ? |
| Barrier | ? | N/A | N/A | release-order undefined |
| Semaphore | ? | FIFO? | count-bounded | ? |
| Mutex | — | N/A | N/A | unfair (os_unfair_lock) |
| Waiter | ? | N/A | N/A | N/A |
| Promise | ? | N/A | single-value | N/A |
| Completion | ? | N/A | N/A | N/A |
| Publication | ? | ? | ? | ? |
| Bridge | sync→async | ? | ? | N/A |
| Timer | deadline | N/A | N/A | N/A |

Every `?` in that table is a load-bearing semantic that currently lives in one docstring, or nowhere. If the table fills in cleanly, the package is production-ready; if filling it in reveals gaps, that's exactly the pre-1.0 work.

Separately, positioning: is this package an alternative to `swift-async-algorithms`, a complement, or a peer? `swift-async-algorithms` has `AsyncChannel` and `AsyncStream` and various operators; this package has `Async.Channel.Bounded` and `Async.Broadcast` with different semantics. A "when to use which" note in the README would save readers a full-reading-of-both-packages to figure out.

---

### Post 6 — @reviewer-c3

<!-- archetype: The closure/expression/syntax technical reviewer (canonical c3) — target: type-system, concurrency, error-handling — opener: thanks — closer: explicit-vote -->

Thanks for the package. Quick technical observations on the shape of the API at the expression level.

`Async.Mutex<State>` with the `locked` coroutine-based accessor at `Sources/Async Mutex Primitives/Async.Mutex.swift` — the comment there says "The `locked` accessor uses `_read` with `nonmutating _modify` on the view, so Mutex works correctly with `let` bindings on classes." This is the right shape for ownership-sensitive state, and avoids the `Optional<State>` + `.take()!` dance I've seen elsewhere in the ecosystem. Nice.

Concern: the underlying primitive is `os_unfair_lock`, which is an unfair lock by Apple's own documentation. For a mutex named `Async.Mutex`, the default-unfair behaviour is surprising. Reference `parking_lot::Mutex` (Rust) is unfair by default too, but calls that out. I'd want the docstring to say explicitly "unfair; prefer Semaphore for ordered access". Right now the comment says "Uses `os_unfair_lock` for mutual exclusion" but doesn't flag the fairness consequence.

The `Async.Channel.Bounded.Ends` type at `Sources/Async Channel Primitives/Async.Channel.Bounded.Ends.swift:20` — I like the shape (one type that exposes both `.sender` and `.receiver` as ends of the same channel), but the `close()` at line 52 and the `receiver` at line 37 and the `send` on `Ends.sender` all share a storage reference. Worth a short API note in DocC about which end owns the lifecycle (is `ends.close()` equivalent to dropping all Senders, or is it a forced close that also cancels receives?).

Typed throws are well-deployed. 42 `throws(E)` declarations is the right posture for a concurrency primitives package — the cancellation errors are concrete, not `any Error`. Tiny nit: I spotted 12 `throws` (untyped) in the source — likely these are deliberate and in cases where the error type is already constrained by protocol conformance, but a quick audit pass to make sure none of them are oversights would be worthwhile before 1.0.

+1 overall, with the asks above.

---

### Post 7 — @reviewer-c4

<!-- archetype: The constructive Evolution-process reviewer (canonical c4) — target: evolution-process, naming, concurrency — opener: question — closer: explicit-vote -->

One framing question on composition with SE-0304.

Structured concurrency (SE-0304) gives us cooperative cancellation propagation through `Task.isCancelled` checks and throwing cancellation errors. A well-composed primitive should either (a) observe cancellation and throw through, or (b) document that it's non-observing and explain why (e.g. a `Mutex` acquisition is synchronous and non-cancelling by design).

Walking the 13 primitives: Channel, Broadcast, Barrier, Semaphore, Waiter, Promise, Completion, Publication, Bridge, Timer all have `async throws(...)` entry points that should observe cancellation. Mutex is synchronous and shouldn't. Good. But for the async ones, I'd want each docstring to have a one-liner "Cancellation: throws `Error.cancelled` if the current task is cancelled during the operation" or similar, *consistently phrased*. I sampled four docstrings and got four slightly-different phrasings. This is exactly the shape of thing the Semantics DocC article @reviewer-c9 proposed would enforce.

Also: how does this compose with `withTaskGroup`-spawned child tasks holding e.g. `Async.Semaphore.Token`? If the outer `withTaskGroup` throws, children are cancelled cooperatively; does the Token's deinit release the permit correctly from within a cancelled task? This is the class of correctness property that's hard to test (requires cancellation injection + permit-count invariant checking) but is exactly what a primitives package earns its keep on.

Overall +1, this is the shape of package the ecosystem needs. The asks are documentation-shaped, not design-shaped.

---

### Post 8 — @reviewer-c2

<!-- archetype: The ~Copyable / Sendable / protocol-shape reviewer (canonical c2) — target: concurrency, type-system, naming — opener: meta-comment — closer: recommendation -->

First a broader observation, then a specific ask.

The package has **157 `~Copyable` type declarations and 116 `Sendable` conformances**. Per `MEMORY` entries in sibling packages, the Institute's policy is to prefer *checked* `Sendable` over `@unchecked Sendable` wherever possible. A quick grep across `Sources/` would surface: (a) how many of the 116 Sendable conformances are conditional (`: Sendable` with constraints), (b) how many are `@unchecked Sendable`, (c) which of the `@unchecked` cases can be upgraded to checked now that Swift 6.3+ has matured the sending/region analysis.

My ask: a pre-1.0 audit pass, and a Research note that enumerates every `@unchecked Sendable` with a two-line justification ("uses raw pointer — intentional, storage is private and all accesses synchronised through Mutex"). This protects the package against a future Swift release that tightens one of the corners and silently breaks a previously-unchecked conformance.

Specifically concerning: `Async.Channel.Bounded.Sender` at `Sender.swift:45` is declared `public struct Sender: Sendable` (checked). Good. But the underlying `Handle` and `Storage` types the Sender wraps — are those `Sendable` by construction (value types composed of Sendable parts) or `@unchecked` because they wrap a raw-pointer descriptor? The docstring doesn't say; worth documenting.

Recommendation: add the `@unchecked Sendable` inventory as a prerequisite for 1.0, and the Semantics DocC article as a prerequisite for 1.0 (echoing @reviewer-c9 / @reviewer-c10).

---

### Post 9 — @reviewer-c7

<!-- archetype: The init/deinit/lifecycle reviewer (canonical c7) — target: concurrency, evolution-process, naming — opener: thanks — closer: explicit-vote -->

Thanks — concerns are around the lifecycle shape of the handle types.

Specifically, **the auto-close-on-last-Sender-drop semantic** is a deinit-mediated contract. `Async.Channel.Bounded.Sender` at `Sender.swift` describes "When the last `Sender` copy is dropped (all references released), the channel automatically closes, waking any waiting receivers." That's implemented through the Sender's deinit (or equivalent ARC mechanism on the Handle). Three concerns with this pattern in Swift-6-era isolation:

1. **Deinit on captured senders.** A Sender captured in a `@Sendable () -> Void` closure is deinited when the closure is released. If the closure is held inside an `actor`'s stored property, the Sender's deinit runs on the actor's executor when the closure is dropped. Is that always safe, or does closing the channel from an actor-isolated deinit cause reentrancy issues with pending receives?

2. **Cancellation-initiated close vs last-drop close.** If a Task holding the last Sender is cancelled mid-`send`, the `send` throws cancellation, the Sender is released as the Task unwinds, and the channel auto-closes. Is this the intended sequence — do receivers see "channel closed" or "element not sent" first? Observable ordering matters.

3. **Close method on `Ends`.** `Async.Channel.Bounded.Ends.close()` at `Async.Channel.Bounded.Ends.swift:52` — is this a forced close (cancels pending receives immediately) or a graceful close (lets pending sends drain)? The docstring at `Ends.swift:37` on the `receiver` property says "the receive-end of the channel" but doesn't cover the close semantics.

These are load-bearing for users who'll reach for Channel in actor-heavy code — which is the use case. Worth explicit documentation of (1), (2), (3) before 1.0. The implementation is probably correct; the contract is under-specified.

+1 once the close-semantic docs land.

---

### Post 10 — @reviewer-c6

<!-- archetype: The Core-Team-aware process voice (canonical c6) — target: evolution-process, naming, type-system — opener: direct-stance — closer: explicit-vote -->

Focused question on SemVer across the 14-product surface.

`swift-async-primitives` is a superrepo with 14 library products. Each product is a separately-importable module: `Async_Primitives_Core`, `Async_Channel_Primitives`, `Async_Barrier_Primitives`, and so on. A downstream consumer pinning on this package pins on **one** version, but gets **14** API surfaces that version commits to.

Three process questions before 1.0:

1. **Is there one version or fourteen?** If the package tags v1.0 tomorrow, is the `Async.Channel.Bounded` API at 1.0 and frozen, while `Async.Publication` is still exploratory? Or does v1.0 mean all 14 products are simultaneously frozen? The answer determines whether it's safe to use the "stable" primitives from a pre-1.0 release.

2. **How do breaking changes in one product affect the version?** If `Async.Barrier` gets a breaking API change in v1.1, does the superrepo bump to 2.0 (because one product broke) or stay at 1.x (because the "unaffected" products are unchanged)? Both answers are defensible, but they produce very different consumer experiences.

3. **Per-product SemVer via separate tags?** Has the Institute considered per-product tags (e.g. `async-channel-primitives-1.0`, `async-barrier-primitives-1.1`) rather than a monolithic package tag? SwiftPM doesn't natively support this but some ecosystems (rust-workspaces, monorepo node packages) do. If this package is going to live at 14-product granularity long-term, per-product versioning may be less misleading than a single umbrella tag.

I'm +1 on the package. The process question is about what "1.0" commits to for each of the 14 module surfaces.

---

### Post 11 — @reviewer-c5

<!-- archetype: The pointed -1 reviewer (canonical c5) — target: evolution-process, naming, error-handling — opener: question — closer: question-to-author -->

-1, narrowly, on one specific choice, and a broader concern.

**Specific -1**: `Async.Mutex<State>` at `Sources/Async Mutex Primitives/Async.Mutex.swift` is gated `#if !hasFeature(Embedded) && canImport(Darwin)`. That means `Async.Mutex` exists on Darwin but does not exist on Linux, Windows, or embedded. The package README headlines "Swift Embedded compatible" but the Mutex — arguably the most load-bearing primitive in the whole package — is Darwin-only.

Linux has `pthread_mutex_t`; Windows has `SRWLock`; embedded-no-OS has nothing-native-but-you-roll-your-own. For a package billed "Swift Embedded compatible", shipping a Mutex that isn't available on non-Darwin platforms is a portability regression relative to even the pthreads baseline. The rest of the package gates on `#if !hasFeature(Embedded)` alone (i.e. Linux/Windows-compatible); only Mutex gates on Darwin-only.

Either (a) add a Linux/Windows implementation of `Async.Mutex` (using `pthread_mutex_t` / `SRWLock`) before 1.0, or (b) rename to `Async.Darwin.Mutex` and be honest about the platform scope, or (c) document explicitly in the README that the Mutex primitive is Darwin-only and that Linux/Windows users must compose their own via a lower-level `Synchronization` primitive. Current state is surprising.

**Broader concern**: Taking the `os_unfair_lock`-backed Mutex together with the 14-product granularity: the package has a fairness problem and a portability problem and a granularity-commitment problem, all at once. Before 1.0, I want the Semantics table @reviewer-c10 proposed to exist AND the portability answer to Mutex AND the SemVer-across-products answer @reviewer-c6 raised. Without all three, the "primitives" framing overreaches — a primitive that only exists on one platform isn't a primitive.

Could be I'm missing a story here. Is there a Linux Mutex sibling in swift-executors or swift-kernel that's the intended partner, and `Async.Mutex` is narrowly the Darwin wrapper?

---

### Post 12 — @op (follow-up)

<!-- archetype: OP follow-up — consolidating responses -->

Thank you all — triaging into action items grouped by theme.

**Semantics documentation** (raised by @c9, reinforced by @c10, @c4, @c8, @c2). Gate for 1.0:
- A top-level DocC article titled "Semantics" with the cancellation / ordering / backpressure / fairness table @reviewer-c10 proposed.
- Filling the table in is the actual pre-1.0 work — every `?` cell either has a correct answer (document it) or reveals a gap (fix it before tagging).

**Lifecycle & close semantics** (@c1, @c7, @c10, @c3).
- Docstring expansion on `Sender`/`Handle` ARC mechanics to make explicit "copying a Sender increments the channel's sender-handle refcount; channel auto-closes when all copies across all tasks are released."
- Close-semantic specification on `Ends.close()` (forced vs graceful).
- Tests exercising cancellation-during-send and actor-captured-sender-deinit paths.

**SemVer posture** (@c6, @c8). Gate for 1.0:
- Explicit README section stating "v1.0 commits all 14 products simultaneously; breaking change in any product is a package-level major bump." (I think that's the right choice; the per-product-tags route is not supported by SwiftPM today and I don't want to invent infrastructure.)
- Product-granularity stays at 14. Accepting the contract commitment.

**Mutex portability** (@c5). Blocker for 1.0:
- Agreed the Darwin-only Mutex is a portability regression inconsistent with the package's framing. Will either add Linux (`pthread_mutex_t`) and Windows (`SRWLock`) implementations before 1.0, or rename to `Async.Darwin.Mutex` and document narrowly. Leaning toward (a) — the whole point of shipping a Mutex at this layer is cross-platform.
- Separately: the "unfair-by-default" point from @c3 is legitimate; will add the fairness disclaimer to the Mutex docstring regardless of platform.

**Sendable audit** (@c2). Gate for 1.0:
- Audit pass across the 116 Sendable conformances, enumerate `@unchecked` instances in `Research/sendable-conformance-inventory.md` with per-case justification.

**swift-async-algorithms positioning** (@c10, @c4).
- README section "When to use `swift-async-primitives` vs `swift-async-algorithms`" — Algorithms ships operators over `AsyncSequence`; this package ships raw coordination primitives. They compose rather than compete, but users will reach for the wrong one if not told.

**Typed throws audit** (@c3).
- Quick pass over the 12 untyped `throws` sites to confirm each is deliberate (protocol-conformance-constrained or similar) and not an oversight.

**Naming** (@c1 on `immediate`).
- `receiveImmediate()` vs `.receive(.immediate)` vs `immediate` as-is — will look at call-site ergonomics across the test suite and Research/ experiments and pick the form that reads best. Leaning toward `.receive(.immediate)` with an explicit option type, matches the ecosystem's `.Options` convention.

No v1.0 tag until the above land. Thank you for the depth.
