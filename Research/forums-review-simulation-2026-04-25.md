---
package: swift-async-primitives
path: /Users/coen/Developer/swift-primitives/swift-async-primitives
simulated_date: 2026-04-25
predicted_category: related-projects
corpus_state: full (602 threads, 25,428 posts, 11,674 substantive)
skill_version: v1.2 (FREVIEW-001..018, venue-stratified + era-corrected)
venue_base_rates: stratified:related-projects (n=224)
era_correction: swift6-era (per-angle multipliers applied)
terminal_posture: not detected
seed: 3
package_head: 01c1c5e
baseline_reference: Research/forums-review-simulation-2026-04-24.md
delta_intent: re-render against current state after the 2026-04-24 launch-readiness mitigation work landed (Semantics article, README versioning + async-algorithms positioning, Sendable inventory, Mutex portability via typealias backends, Lifecycle.Error consolidation, Async.Barrier Shape A typed-throws, withPermit Either fix, Completion.Error.cancellation → .cancelled rename)
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

# Simulated Swift Forums review — `swift-async-primitives`

> Internal simulation per the `swift-forums-review` skill. Statistically-grounded archetypes responding to a related-projects-style announcement of the package at HEAD `01c1c5e`. Not real reviewers, not real posts. Regenerated 2026-04-25 against the current state to measure deltas vs the 2026-04-24 baseline now that the launch-readiness mitigation work has landed.

---

### Post 1 — @op

Hi all,

I've tagged a release candidate of `swift-async-primitives` — an Apache-2.0 L1 package in the Swift Institute primitives ecosystem that bundles 11 coordination primitives under a single `Async` namespace, shipped as 14 separate library products.

The coordination surface, in one screen:

```
Async.Channel.Bounded<Element: ~Copyable>      - bounded buffer, single-receiver, multi-sender via Sender clone
Async.Channel.Unbounded<Element: ~Copyable>    - unbounded buffer, single-receiver
Async.Broadcast<Element>                        - SPMC broadcast with replay window
Async.Barrier                                   - party-count barrier with cancellation rollback
Async.Semaphore                                 - FIFO counting semaphore
Async.Mutex<Value: ~Copyable>                   - portable value-owning mutex (Darwin / Synchronization / Kernel.Thread / no-op)
Async.Promise<Value>                            - single-value handoff, non-cancellation-observing by signature
Async.Completion                                - void terminal-result with CAS-mediated transitions
Async.Publication                               - latest-value-wins atomic take
Async.Bridge                                    - sync-to-async handoff
Async.Timer                                     - async deadline (also a namespace for Timer.Wheel)
```

Plus building-block namespaces (`Async.Waiter` for low-level suspension, `Async.Lifecycle` for the shared `shutdown / cancelled / timeout` error envelope) used to compose the coordination primitives.

The package ships 15 targets / 14 public products so consumers can pull narrow variant modules — `import Async_Channel_Primitives`, `import Async_Mutex_Primitives` — rather than dragging the full umbrella through every dependency. The README's "Importing" section names this as the recommended pattern.

Highlights of the design posture (most of these landed since an internal forums-review simulation pass on 2026-04-24):

1. **Per-primitive `Semantics` DocC article**. `Sources/Async Primitives/Async Primitives.docc/Semantics.md` tabulates cancellation observation / ordering / backpressure / fairness across all 11 coordination primitives — every cell filled, no `gap` rows.
2. **Typed throws everywhere**. 41 typed-`throws(E)` sites in `Sources/`; 0 untyped. Audit at `Research/typed-throws-audit-2026-04-24.md`.
3. **Cancellation-error envelope**. `Async.Lifecycle.Error` is non-generic with cases `.shutdown / .cancelled / .timeout`. Per-primitive errors typealias to it where all three cases apply (Semaphore), and stay per-primitive where they don't (Channel mixes `.cancelled` with `.full / .empty / .closed`; Broadcast and Completion likewise).
4. **`Async.Mutex<Value: ~Copyable>` is portable**. Darwin uses `os_unfair_lock`-backed raw layout; non-Darwin with `canImport(Synchronization)` typealiases to `Synchronization.Mutex`; non-Darwin with `Kernel.Thread.Mutex.Value` typealiases to that; embedded falls through to a no-op single-threaded variant. Fairness disclaimer in the docstring.
5. **`@unchecked Sendable` inventory** at `Research/sendable-conformance-inventory.md`: 5 unconditional `@unchecked` sites, each justified.
6. **`Async.Barrier.arrive()`** uses typed throws and adapts effective party count on mid-await cancellation: `arrive() async throws(Async.Lifecycle.Error)`. The cancelled party rolls back from `arrived` and increments `cancelledCount`; the release condition becomes `arrived == parties - cancelled`.
7. **`Async.Semaphore.withPermit`** returns `Either<Async.Semaphore.Error, E>` — `.left` is an acquisition failure, `.right` is a body failure. Avoids existential error erasure when composing the body's domain errors with the semaphore's lifecycle errors.
8. **Stability and versioning** section in README documenting the package-level vs per-product question (as candidly as I can — the swift-institute-level posture across products is still being settled).

What I'm looking for: feedback on whether the Semantics article actually closes the per-primitive contract questions a careful reader will have; on the `Either<…, E>` return shape vs alternatives; on whether the README's candid "pending resolution" framing of the 14-product SemVer question reads as a deferred problem or a reasonable commitment-shape; and on residual API ergonomics that haven't landed yet.

Code is at `Sources/` (one product per directory, named after the namespace). Per-primitive design rationale is in `Research/`. I'd particularly value pushback on anything that reads as documentation-shaped completeness when the underlying contract is still vague.

---

### Post 2 — @reviewer-c1

<!-- archetype: The general-purpose technical reviewer (canonical c1) — angles: concurrency, evolution-process, type-system — opener: question — closer: question-to-author -->

Read through the README, the `Semantics` article, and the channel sources. One thing to clarify before I form a stance.

The `Receive` accessor at `Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.Receive.swift:17` is a `Sendable` struct exposing `immediate()` and (presumably) the suspending variants. The naming on the `Send` side is symmetric: `Sources/Async Channel Primitives/Async.Channel.Bounded.Sender.Send.swift:36` declares `func immediate(_ element:) throws(Async.Channel<Element>.Error)`. I like the structure — a `receive` / `send` accessor that namespaces the variants — but I want to verify two things.

First, is the intent that consumers always go through `receiver.receive.immediate()` and `sender.send.immediate(x)`, or are top-level fast-path methods (`receiver.receiveImmediate()`, `sender.sendImmediate(x)`) deprecated / not present? The Semantics table cites the typed-throws cancellation contract on receive's suspending form but doesn't talk about the accessor-shape ergonomics. Worth a one-sentence README-or-docstring note: "operations are reached through `.receive` / `.send` accessors that namespace the variants" — right now the shape is discoverable only by reading the source.

Second, the `Receive` struct is `Sendable`. It captures `storage`, which is `Async.Channel<Element>.Bounded.Storage`. Is `Storage` a `~Copyable` reference-type wrapper or a value type? If it's a value carrying a non-trivial refcount, the `Sendable` claim on `Receive` rests on whatever invariant the underlying lock + storage provides. The Semantics article handles this at the operational level (FIFO via Deque, lock-acquisition order); a one-line note on the Receive/Send accessor structs themselves about how the Sendable claim composes would close the gap.

Otherwise, the package shape reads as deliberate. Is there a design doc for the receive-family / send-family accessor pattern, or is it a Swift-Institute convention I should grep the sibling packages for?

---

### Post 3 — @reviewer-c9

<!-- archetype: The long-form deep-analysis essay reviewer (canonical c9) — angles: concurrency, evolution-process, type-system — opener: thanks — closer: question-to-author -->

Thanks for shipping this, and particularly for actually landing the `Semantics` article — that closes ~70% of the kind of pre-flight questions I'd otherwise be raising one-by-one. Reading through `Sources/Async Primitives/Async Primitives.docc/Semantics.md` plus the per-primitive sources, a handful of things still want pushback before this is a confident +1.

**Linearizability claims in the table read clean, with one inconsistency.** The Broadcast row says "Per-subscriber FIFO for delivered items. Across subscribers on a single `send(_:)`: subscription-order resume … Resume-call order differs from task-completion order, which is scheduler-determined." That's the right shape — the primitive controls who-gets-resumed-first; the runtime controls who-runs-first. Good. But the §Cancellation-error naming consistency block at the bottom of the article says "`Async/Completion/Error` uses `.cancellation` (noun) — per-primitive enum, the lone outlier." The actual source at `Sources/Async Completion Primitives/Async.Completion.Error.swift:21` declares `case cancelled`. The article describes a state of affairs that no longer holds — the rename landed, the documentation didn't follow. That's a small thing, but the §Cancellation-error block is precisely the place a reviewer goes to verify naming consistency, and finding it stale is exactly the kind of credibility hit that turns a +1 into "let me re-verify everything."

**Barrier Shape A is a real commitment.** `Sources/Async Barrier Primitives/Async.Barrier.swift:225` has `func arrive() async throws(Async.Lifecycle.Error)`. The Semantics row for Barrier explains the effective-party-count adaptation: "remaining parties release when `arrived == parties - cancelled`." That's a contract I want, and I want to verify two things: (a) the `cancelledCount` accessor at `Async.Barrier.swift:195` is the way external observers see the rollback — is that intended public API, or should it be `package`/internal? (b) The "cancelled-before-`arrive()`" case (a Task is cancelled before it ever reaches the call site) is called out as outside the typed-throws contract. That feels like a real residual gap — a barrier can be deadlocked by a never-arriving party — and the article puts the burden on "structural concurrency", which is correct but worth one explicit example showing how a `withTaskGroup` arrangement makes the deadlock impossible.

**Semantics article doesn't talk about `Async.Bridge` next() under cancellation in the body of the table.** The Bridge row says "Non-observing by signature" with `next()` returning `Element?` (no throws). The cited test path at `Sources/Async Bridge Primitives/Async.Bridge.swift:133` is the suspending fast-path. That's fine, but the precondition at line ~136 traps if a second consumer calls `next()` concurrently. Is that "single-consumer invariant" considered a contract-level claim? If so, it deserves explicit callout in the article's row, not just an inline `precondition`. If it's enforcement-only, a `package`-level test that verifies the trap fires deterministically would help.

**Channel.Bounded multi-sender ordering is now documented (good), but one corner-case worth pinning.** The article says "Mutex-acquisition order — concurrent `send(_:)` calls from distinct Senders serialize on the storage lock; elements appear in buffer (and at receiver) in lock-acquisition order. Per-sender FIFO is preserved." Excellent. But the auto-close path: when the last `Sender` is dropped while a `send` is pending in another task, the close completes via the dropped Sender's deinit. Does that deinit-driven close interact correctly with the lock-acquisition order? I.e., is "close observed before pending element" possible, or does close serialize through the same lock? The Sender file's expanded ARC docstring (`Async.Channel.Bounded.Sender.swift:24-39`) names the mechanism but stops short of the ordering claim.

Are these enough to keep this a few-week soak rather than a 1.0 tag?

---

### Post 4 — @reviewer-c8

<!-- archetype: The SwiftPM / build-tooling / modularity reviewer (canonical c8) — angles: layering-modularity, build-tooling, evolution-process — opener: question — closer: question-to-author -->

`Package.swift` and the README's Stability section.

The README at lines 60–69 commits to "consumers should treat the 14 products as sharing a single package-level version tag and pin accordingly", *until* the swift-institute-level posture lands. That's a candid framing and I respect it, but it leaves a real ambiguity for a downstream consumer: pinning to package v1.0 today commits you to whatever the swift-institute eventually decides, retrospectively. Two questions:

1. **Is "the swift-institute-level posture is pending" a load-bearing 1.0 dependency, or can the package ship 1.0 without that being resolved?** If the package tags v1.0 with the README saying "pending resolution", a consumer pinning v1.0 reads it as "treat all 14 products as one tag for now" — and then the institute resolves the question one way or the other six months later, and either (a) consumer's pinning reads correctly or (b) the institute went per-product-tags and now the consumer's import line is stable but their conceptual model is wrong. Worth deciding *before* tagging which way 1.0 commits.

2. **The `import Async_Primitives_*` recommendation is in the README; the Package.swift doesn't enforce it.** `Async_Primitives` is the umbrella product re-exporting everything; `Async_Primitives_Core` is the no-dep root. The "Importing" section says narrow variants are recommended — good. But there's no warning, deprecation marker, or `@_disfavoredOverload` on the umbrella import to discourage it. Consumers who import the umbrella by reflex still get a working build. Per the Institute's `[feedback_no_umbrella_imports]` (which I'm grepping from sibling packages' conventions), consumers SHOULD import narrow variants. Is the convention enforced anywhere — a build-warning, a doc deprecation — or is it documentation-only?

3. **Embedded gating posture.** `Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.swift` (and most of the channel sources) are gated `#if !hasFeature(Embedded)` at file-level — the symbols don't exist on embedded. `Async.Channel.Bounded.Receive` at `Async.Channel.Bounded.Receiver.Receive.swift:13` is the same shape. That means an embedded consumer who imports `Async_Channel_Primitives` gets a successful import of an empty module — no symbols, no error. Per the Institute's modularization conventions I've seen elsewhere, the more-honest shape is to gate at manifest level (`condition: .when(platforms: [...])`) or at swiftSettings, so embedded builds *can't* import the module at all. The current shape is surprising in the direction of "compiles, does nothing" rather than "fails fast".

I'm not -1 on any of this, but the SemVer question and the import-discipline question are both load-bearing for the related-projects audience, who'll read this as "what does pinning this package commit me to over the next two years."

---

### Post 5 — @reviewer-c10

<!-- archetype: The heavy-quoting long-form authoritative reviewer (canonical c10) — angles: evolution-process, concurrency, type-system — opener: direct-stance — closer: question-to-author -->

Going to thread through the points raised, because they interact.

> [@reviewer-c1] is the intent that consumers always go through `receiver.receive.immediate()` and `sender.send.immediate(x)`, or are top-level fast-path methods deprecated / not present?

The accessor pattern is right for namespacing variants, and it composes with the Institute's nested-name conventions (every variant becomes `<accessor>.<form>` rather than `<form>(<accessor>:)`-style suffixing). That said, c1's ask is fair — one README sentence stating "operations are reached through `.receive` / `.send` accessors that namespace the variants (`.immediate()`, the suspending overload, etc.)" would close the discoverability gap without committing the package to a different shape.

> [@reviewer-c9] §Cancellation-error block at the bottom of the article says "`Async/Completion/Error` uses `.cancellation` (noun) — per-primitive enum, the lone outlier." The actual source declares `case cancelled`.

This is the more concerning observation in the thread, in my read. The `Sources/Async Primitives/Async Primitives.docc/Semantics.md` article is the load-bearing doc artifact for this whole package — the §Cancellation-error block specifically exists to give reviewers like me a single place to verify per-primitive naming. If the source has converged on `.cancelled` everywhere (which a quick `grep -rn "case cancellation\|case cancelled" Sources/` confirms — only `case cancelled`, no `case cancellation` in `Sources/`), then the article needs a single-word fix and a "per-primitive enum, formerly the outlier; aligned 2026-04-25" annotation. Without it, the next reviewer to land here reads the article and either (a) trusts it and writes consumer code against `Completion.Error.cancellation` and gets a build error, or (b) verifies against source and loses confidence in the article. Both bad outcomes; the fix is mechanical.

> [@reviewer-c8] Is "the swift-institute-level posture is pending" a load-bearing 1.0 dependency

I'd argue the package can ship 1.0 with the candid "pending resolution" framing precisely because it commits to the all-14-products-together posture *for the duration of v1.x*. The institute resolution shifts how *future* tags are versioned, not what v1.0 means. The README could be one degree more emphatic: "v1.x: all 14 products treated as one tag. Future major versions may revisit at the institute-wide level." That changes the framing from "pending decision blocking the tag" to "v1.0 commits to one model; v2.0 may revisit."

On `Either<Async.Semaphore.Error, E>`. `Sources/Async Semaphore Primitives/Async.Semaphore+WithPermit.swift:39` declares the function as `async throws(Either<Async.Semaphore.Error, E>) -> sending T`. The shape is correct — it preserves the typed-error contract for both halves of the failure mode without erasing to `any Error`. The receiver-side ergonomics are fine if consumers pattern-match `Either.left` / `Either.right`; they're awkward if consumers want a single domain error. That's not a defect in the package — it's a tradeoff with the typed-throws posture — but worth documenting in `withPermit`'s docstring an example of the pattern-matching consumer site, so readers know the shape they're committing to.

Where does that leave the +1? On the package itself, +1; on the Semantics article, I'd want the §Cancellation-error block updated *before* the v1.0 tag, because that block is the article's most-cited piece for naming-consistency arguments and a stale entry there is precisely the kind of thing reviewers in twelve months will quote back as "oh, the documentation is unreliable."

---

### Post 6 — @reviewer-c3

<!-- archetype: The closure/expression/syntax technical reviewer (canonical c3) — angles: type-system, concurrency, error-handling — opener: thanks — closer: explicit-vote -->

Thanks. Quick technical observations on the shape of the API at the expression level.

`Async.Mutex<Value: ~Copyable>` at `Sources/Async Mutex Primitives/Async.Mutex.swift` reads cleanly now — the file is a single conditional cascade: Darwin uses `os_unfair_lock`-backed raw layout; non-Darwin with `canImport(Synchronization)` typealiases to `Synchronization.Mutex`; non-Darwin with `Kernel_Thread_Primitives` typealiases to `Kernel.Thread.Mutex.Value`; embedded falls through to a no-op single-threaded variant. The fairness disclaimer at lines 27–32 is exactly the right shape: "**unfair by default**" called out as a documented property, with the redirect to compose `Async.Semaphore` for FIFO admission. Good.

The closure shape on `withLock` is `(inout sending Value) throws(E) -> sending T`. That's the right surface for `~Copyable` state: `inout sending` keeps the borrow region intact across the body, the typed `throws(E)` propagates the body's error type without erasure, and the `sending T` return preserves region transfer. I don't have notes on this shape — it's the canonical Swift-6-era pattern.

On `Async.Barrier.arrive()` at `Sources/Async Barrier Primitives/Async.Barrier.swift:225`: the `throws(Async.Lifecycle.Error)` typed-throws is correct for the contract. The callback form at line 180 is `func arrive(_ callback: @escaping @Sendable () -> Void)` — non-observing by design, embedded-compatible. The two shapes coexist cleanly (one suspends and types-through cancellation; one defers via a callback and is non-observing). Worth a one-line note in the type-level docstring naming the two-form distinction explicitly: "`arrive()` for cancellation-observing async sites; `arrive(_:)` for sync/embedded-compatible sites."

On the typed-throws audit. `Research/typed-throws-audit-2026-04-24.md` reports zero untyped `throws` in `Sources/`. The package characterization tool reports 18 untyped sites. The discrepancy is worth resolving in the audit doc itself — my guess is the 18 are macro-expanded test signatures that the audit's Sources/-only filter excluded, but a one-paragraph footnote clarifying the count would close the gap before someone else surfaces the same question and you have to answer it twice.

+1 on the technical posture. Asks are documentation-shaped: the Semantics article §Cancellation-error stale text (per @c9 / @c10), the dual-form Barrier docstring note, the typed-throws-count disambiguation.

---

### Post 7 — @reviewer-c4

<!-- archetype: The constructive Evolution-process reviewer (canonical c4) — angles: evolution-process, naming, concurrency — opener: question — closer: explicit-vote -->

One framing question on the cancellation-error envelope, and a composition observation.

The `Async.Lifecycle.Error` envelope at `Sources/Async Primitives Core/Async.Lifecycle.Error.swift` is a non-generic enum with `.shutdown / .cancelled / .timeout`. The Semantics article's §Cancellation-error consistency block names the principle: typealias a per-primitive error to `Async.Lifecycle.Error` ONLY when all three cases apply. Semaphore satisfies this and typealiases (`Sources/Async Semaphore Primitives/Async.Semaphore.Error.swift:19`); Channel and Broadcast keep per-primitive errors because they have additional domain cases. That's a defensible discipline. Two follow-ups:

1. **The principle is correct; the rollout is partial.** `Async.Completion.Error` has `.cancelled` (after the rename — `Async.Completion.Error.swift:21`), and the Semantics article still names it as the outlier. Either the article gets updated to remove that entry from the outlier list (the obvious fix), *or* — if the principle says Completion's enum should typealias because cancellation is its only lifecycle-shaped case but `.shutdown` and `.timeout` don't apply — the package needs to commit one direction. Currently the principle and the source agree (Completion stays per-primitive because not-all-three-cases-apply); only the documentation lags. Mechanical fix.

2. **Composition with `withTaskGroup`-spawned children.** A child task holding a `Async.Semaphore.Token` (RAII permit handle) — when the outer group throws, children are cancelled. Does the Token's deinit release the permit correctly when the cancelled child unwinds, and does that release path observe `Async.Lifecycle.Error.shutdown` if the semaphore is concurrently shutting down? This is the class of correctness property where the implementation is probably right and the contract is under-specified. Worth one paragraph in the `Token` docstring on the deinit + cancellation + shutdown interaction order, and a test that exercises the racing-shutdown-vs-cancellation case.

The package is in much better shape than it was a week ago — the Semantics article alone closed half the questions I'd otherwise have raised. +1 once the §Cancellation-error block is brought into sync with the source.

---

### Post 8 — @reviewer-c2

<!-- archetype: The ~Copyable / Sendable / protocol-shape reviewer (canonical c2) — angles: concurrency, type-system, naming — opener: meta-comment — closer: recommendation -->

A note on the Sendable surface, then one specific check.

`Research/sendable-conformance-inventory.md` enumerates the `@unchecked Sendable` sites (5 unconditional, the rest checked or constrained). That closes the broad `@unchecked` audit ask cleanly — this is exactly the form I'd want to see across the ecosystem. The inventory's framing — "the load-bearing number for audit purposes is the 5 `@unchecked Sendable` conformances" — is correct: aggregate counts conflate constraints, conformances, and doc mentions; the per-site enumeration is what audit work actually consumes.

One specific check on the `Receive` / `Send` accessor structs. `Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.Receive.swift:17` declares `public struct Receive: Sendable` — checked Sendable. The `storage` property captures `Async.Channel<Element>.Bounded.Storage`. For the checked Sendable claim to hold, `Storage` must be `Sendable` (composable Sendable parts) or `@unchecked Sendable` with a justification (raw-pointer-backed, externally synchronized). Same question for `Sender.Send` at `Async.Channel.Bounded.Sender.Send.swift:36` — its `handle` capture must compose to a checked Sendable claim or be in the inventory. The inventory enumerates 5 sites total; if the Storage/Handle types are among them, fine. If they're checked Sendable through composition, even better — the inventory could note "Receive / Send accessor structs are checked Sendable through Storage / Handle composition" as a positive assertion.

Recommendation: the inventory is the right artifact; one pass to confirm the accessor-struct Sendable claims trace to either the inventory's `@unchecked` list or to a checked-by-composition statement closes the loop. That's the difference between "we know our @unchecked Sendable surface" and "we know our entire Sendable surface is auditable."

---

### Post 9 — @reviewer-c7

<!-- archetype: The init/deinit/lifecycle reviewer (canonical c7) — angles: concurrency, evolution-process, naming — opener: thanks — closer: explicit-vote -->

Thanks — the lifecycle surface has tightened up substantially since the last simulation pass.

`Sources/Async Channel Primitives/Async.Channel.Bounded.Sender.swift:24-39` now has the ARC-Mediated section: "Copying a `Sender` increments the channel's sender-handle refcount; dropping a copy decrements it. When the last `Sender` copy across ALL tasks is released, the channel automatically closes." That's the right shape and addresses the corner where a `Sender` captured in a `@Sendable` closure held by an `actor`'s stored property gets released via the actor's executor — the contract is now documented. Two residual asks:

1. **Actor-isolated deinit + close semantics.** When the closure-held Sender is the last one and the actor's executor runs the deinit, the close-driven receiver wakeup and any pending senders' resume happen as part of that deinit's execution. Is there a test that pins this? `Sources/Async Channel Primitives/Async.Channel.Bounded.Ends.swift:47` — `sender` is a computed property synthesizing a fresh Sender from storage on each access, so an `actor` can hold an `Ends` (`~Copyable, Sendable`) and call `.sender.close()` directly, which is a different lifecycle path from the captured-Sender-released-on-deinit path. Both should be covered.

2. **`Ends` lifecycle and the underlying Receiver.** `Async.Channel.Bounded.Ends.swift:20` declares `public struct Ends: ~Copyable, Sendable`. It contains `_receiver: Receiver` (`~Copyable`). The receiver is exposed via `var receiver: Async.Channel<Element>.Bounded.Receiver` at line 37 with `_read` / `_modify` yielding semantics. `var sender:` at line 47 is a fresh-each-access value type. The asymmetry is intentional — receiver carries cursor / state, sender is a re-derivable view — but worth a one-line type-level note in `Ends` that names the asymmetry. The reader who's about to wrap `Ends` in a `Mutex<Ends>` (a reasonable pattern) needs to know that the receiver's state is in `_receiver` while the sender is recoverable from `storage`.

3. **`elements` as the AsyncSequence view.** `Async.Channel.Bounded.Receiver.swift:154` exposes `var elements: Bounded.Elements` as an AsyncSequence-conforming view, available only when `Element: Copyable`. The "for try await value in receiver.elements" pattern is the obvious consumer ergonomics for the Copyable case. Worth a parallel example in the Semantics article's Channel.Bounded row showing both `receive()` (for `~Copyable`) and `for try await` (for `Copyable`) — currently the table shows the contract but not the consumer-site shape.

+1 once the actor-deinit close path has explicit test coverage and the `Ends` asymmetry is documented.

---

### Post 10 — @reviewer-c6

<!-- archetype: The Core-Team-aware process voice (canonical c6) — angles: evolution-process, naming, type-system — opener: direct-stance — closer: explicit-vote -->

Focused observation on the SemVer-across-products framing in the README.

`README.md:60-69` (the "Stability and versioning" section) handles the question I would have raised — what does v1.0 commit to across 14 products — by acknowledging the swift-institute-level posture is pending and providing a concrete interim contract: treat all 14 products as one package version. Good.

Three notes:

1. **The framing reads as "deferred" rather than "decided."** Reviewers will read "pending resolution at the swift-institute level" as "the author hasn't picked a side yet." Per @reviewer-c10's framing upthread, this can shift to "v1.x commits to one model; v2.0 may revisit" which is a *commitment* rather than a *deferral*. Same content, different read.

2. **`Async.Bridge` next() is not in the public API quick-reference.** `Sources/Async Bridge Primitives/Async.Bridge.swift:133` declares `nonisolated(nonsending) public func next() async -> Element?`. The Semantics article's Bridge row covers it; the README's coordination-surface code block in the OP doesn't show a `Bridge` example. Worth one in the README — Bridge is the primitive most likely to be reached for by AppKit/UIKit-style code that wants to feed a sync producer into an `AsyncSequence`-shaped consumer, and that's exactly the related-projects audience.

3. **`Async.Barrier.cancelledCount` as public API.** `Async.Barrier.swift:195` exposes `public var cancelledCount: Int`. This is the observable surface of the Shape A effective-party-count design. Is exposing it part of the contract — i.e., consumers *should* be able to read "how many parties were cancelled mid-await" — or is it diagnostic surface that should be `package`-level? Either is defensible; tagging which it is in the docstring would help. The Semantics article doesn't currently distinguish.

+1 once the README's framing is explicitly committal rather than candidly-deferred. The substance is fine.

---

### Post 11 — @reviewer-c5

<!-- archetype: The pointed -1 reviewer (canonical c5) — angles: evolution-process, naming, error-handling — opener: question — closer: question-to-author -->

I want to find a -1 here, and the package has closed most of the targets the previous simulation reached for. The Mutex is portable now (`Sources/Async Mutex Primitives/Async.Mutex.swift` is a four-branch conditional cascade hitting Darwin / Synchronization / Kernel.Thread / no-op embedded). The Semantics article exists. The Sendable inventory exists. Versioning is candidly framed. So this isn't a "package shouldn't ship" critique. It's a narrower one.

**Narrow -1**: the load-bearing documentation artifact for this package — `Sources/Async Primitives/Async Primitives.docc/Semantics.md` — has stale §Cancellation-error content. Specifically, that block says `Async/Completion/Error` "uses `.cancellation` (noun) — per-primitive enum, the lone outlier." The source disagrees: `Sources/Async Completion Primitives/Async.Completion.Error.swift:21` declares `case cancelled`. A reviewer who reads the Semantics article and writes consumer code against `.cancellation` gets a compile error; a reviewer who verifies the article against source loses confidence in the article overall. The Semantics article is the package's primary "you-can-trust-this-doc-as-the-contract" surface. Stale content there is a different category of defect from "this primitive's contract isn't documented" — it's "the documentation contradicts the source", which is worse for trust. -1 on tagging 1.0 with the stale text in place.

**Less narrow concern**: `Sources/Async Channel Primitives/Async.Channel.Bounded.Ends.swift:47` exposes `var sender: Sender` as a fresh-each-access computed property. `Async.Channel.Bounded.Ends.swift:37` exposes `var receiver: Receiver` with `_read` / `_modify` yielding the stored `_receiver`. The asymmetry is real and intended (per the lifecycle of `~Copyable` Receiver vs `Copyable` Sender), but reading the source cold, the two properties look symmetric and behave differently. A consumer doing `let s1 = ends.sender; let s2 = ends.sender` gets two distinct Sender values that happen to share storage; the mental model "I'm aliasing the same accessor" is wrong. The fix is documentation: the `var sender` declaration needs a one-line note that it synthesizes a Sender per-access. Without that, the asymmetry is a foot-gun for consumers who copy Senders for distinct producers expecting that copying-the-property is the same as `let s2 = s1` — and per the ARC-Mediated docstring at `Sender.swift:24-39`, the two are different semantically (one is a per-call synthesis, the other is a refcount-incrementing copy of an existing handle).

`Sources/Async Broadcast Primitives/Async.Broadcast.swift:177` — `func finish()` — is the canonical Broadcast termination. Its docstring at lines 173-176 says "All pending receives return remaining buffered elements, then `nil`. Future `send()` calls are silently ignored." That's a fine contract. But "silently ignored" is a designed-in choice that some users will read as a footgun — they expect a closed-channel send to throw, by analogy with `Async.Channel.Error.closed`. Either the contract gets a one-line "by design — Broadcast is fire-and-forget on the producer side" note, or `Broadcast.send` gets a `Broadcast.Error.finished` typed throw to preserve symmetry with Channel. Pick one.

Could be I'm wrong on the §Cancellation-error block — is it possible the source has been renamed and the article just hasn't been refreshed yet, in which case "fix the article" is the answer and the -1 dissolves into a typo correction?

---

### Post 12 — @op (follow-up)

<!-- archetype: OP follow-up — consolidating responses -->

Thank you all — the substance is much sharper than the 2026-04-24 pass, and the load-bearing concerns concentrate around two clusters.

**Documentation/source consistency** (raised by @c9, reinforced by @c10, @c4, @c5). Single load-bearing fix:
- `Sources/Async Primitives/Async Primitives.docc/Semantics.md` §Cancellation-error block names `Async.Completion.Error` as using `.cancellation` (the outlier). The source landed `case cancelled` (commit 7e893ae). Mechanical fix: update the article's text and remove the "lone outlier" framing. Will be done before any 1.0 tag. The criticism is fair — the article is the primary contract artifact, and stale text there is precisely the wrong place for a typo.

**Lifecycle / accessor-shape clarity** (@c1, @c7, @c5).
- README will get one sentence on the accessor pattern: "operations are reached through `.receive` / `.send` accessors that namespace variants (`.immediate()`, suspending overload)."
- `Async.Channel.Bounded.Ends` will get a type-level docstring naming the `receiver` (stored, `_read`/`_modify`) vs `sender` (synthesized per access) asymmetry. The current ARC-Mediated docstring on `Sender` is the right shape; the asymmetry vs `receiver` needs to be visible at the `Ends` type level.
- A test exercising the actor-isolated deinit close path (@c7's ask 1) is realistic pre-1.0; will land alongside the docstring update.

**Versioning framing** (@c8, @c10, @c6).
- README "Stability and versioning" framing will shift from "pending resolution" to "v1.x commits to package-level versioning across all 14 products; v2.0 may revisit at the institute-wide level." Same content, decided framing.
- Embedded-gating posture (@c8 ask 3) — file-level `#if !hasFeature(Embedded)` vs manifest-level `condition: .when(platforms:)` — is an open question worth a separate Research note. The current shape (compile-empty-on-embedded) was deliberate to allow shared product-name imports across embedded and non-embedded consumers; manifest-level gating would force two product names. Will think.

**Sendable surface confirmation** (@c2).
- The accessor-struct Sendable claims trace to checked-by-composition through `Storage` / `Handle`. Will add a positive-assertion paragraph to `Research/sendable-conformance-inventory.md` so the inventory covers "we know our entire Sendable surface", not just "we know our `@unchecked` surface."

**Barrier surface** (@c9, @c10, @c6).
- `cancelledCount` public-vs-`package`: leaning public — it's the observable surface of Shape A's effective-party adaptation, and `Research/barrier-api-investigation-2026-04-25.md` reasoned through the case for it. Will add a docstring sentence naming it as part of the contract, not diagnostic surface.
- The "cancelled-before-`arrive()`" deadlock case (@c9): will add a structural-concurrency `withTaskGroup` example in the Barrier docstring or Semantics article showing the `arrive()` site composed with cancellation propagation.

**Bridge** (@c6, @c9).
- `Async.Bridge` example in README coordination surface (the AppKit/UIKit feed-into-AsyncSequence shape). Reasonable; adds ~10 lines.
- Single-consumer invariant: precondition trap is current. Will pin the test as @c9 asked.

**Broadcast.finish()** (@c5).
- The "silently ignored" framing for post-finish `send` is the design choice (Broadcast is fire-and-forget on the producer side — there's no per-send recipient acknowledgement, so a producer-side error wouldn't reach the right consumer). Will add the one-line "by design" note rather than introducing `Broadcast.Error.finished`.

**Typed-throws count** (@c3).
- The 18-vs-0 discrepancy (characterizer vs audit): the characterizer counts `func … throws ` patterns including a few in macro-expanded test signatures. Audit doc will get a footnote naming the source/test split. Mechanical.

Net: the package is closer to launch-ready than the 2026-04-24 pass implied. The single new must-fix is the Semantics article §Cancellation-error stale text. Rest are tightening, not designing.
