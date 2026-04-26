---
source_simulation: forums-review-simulation-2026-04-25.md
triage_date: 2026-04-25
rule: FREVIEW-012 + FREVIEW-018
pre_classification_automated: true
human_review_complete: true
human_reviewer_notes: source-verification per [FREVIEW-018] applied to every load-bearing-classified post; anchor-grounded factual claims checked against current Sources/, Research/, README, and DocC catalog at HEAD 01c1c5e
---

# Concreteness-anchor triage — forums-review-simulation-2026-04-25

Pre-classifications are produced by `scripts/triage_simulation.py` using the concreteness-anchor regex catalogue. **Final classifications and dispositions are filled in below per [FREVIEW-012]** with anchor-grounded claims source-verified per [FREVIEW-018]. The simulation thread anchors are accurate to current source; the substantive accuracy of each post's claim was checked against the file/line cited.

Quoted blocks (Discourse-style `> text` lines) and fenced code blocks are excluded from the count — they don't count as the post author's own anchoring.

| # | handle | archetype | anchor total | pre-classification | final classification | disposition |
|---|---|---|---:|---|---|---|
| 1 | @op | — | 10 | op-follow-up | op-follow-up | n/a — OP framing post |
| 2 | @reviewer-c1 | The general-purpose technical reviewer (canonical c1) | 4 | load-bearing-candidate | **load-bearing** | act-on (claims verified): one-sentence README note on `.receive` / `.send` accessor pattern + Sendable-claim-composition note on accessor structs |
| 3 | @reviewer-c9 | The long-form deep-analysis essay reviewer (canonical c9) | 9 | load-bearing-candidate | **load-bearing** | act-on (claims verified): the §Cancellation-error stale-text finding is the headline new critique, see Calibration notes; remaining asks (cancelledCount API contract clarification, Bridge single-consumer trap test, Channel close-vs-pending-element ordering claim) are documentation-shaped |
| 4 | @reviewer-c8 | The SwiftPM / build-tooling / modularity reviewer (canonical c8) | 8 | load-bearing-candidate | **load-bearing** | act-on (claims verified): README versioning framing should shift from "pending resolution" to "v1.x commits all-products-together; v2.0 may revisit"; embedded-gating posture (file-level `#if` vs manifest-level) is a real design choice worth a separate Research note |
| 5 | @reviewer-c10 | The heavy-quoting long-form authoritative reviewer (canonical c10) | 5 | load-bearing-candidate | **load-bearing** | act-on (claims verified): doubles down on the Semantics §Cancellation-error stale text via independent grep of source — same finding as @c9, reinforced; `withPermit` Either-shape consumer-site example in docstring is a useful tightening |
| 6 | @reviewer-c3 | The closure/expression/syntax technical reviewer (canonical c3) | 5 | load-bearing-candidate | **load-bearing** | act-on (claims verified): Mutex fairness disclaimer wording, withLock signature shape, and Barrier dual-form distinction all check out; ask is dual-form Barrier docstring note + typed-throws-count footnote disambiguation |
| 7 | @reviewer-c4 | The constructive Evolution-process reviewer (canonical c4) | 7 | load-bearing-candidate | **load-bearing** | act-on (claims verified): Lifecycle.Error envelope and Semaphore.Error typealias check out; Token deinit + cancellation + shutdown interaction docstring is real residual gap |
| 8 | @reviewer-c2 | The ~Copyable / Sendable / protocol-shape reviewer (canonical c2) | 3 | load-bearing-candidate | **load-bearing** | act-on (claims verified, with one minor anchor-position imprecision): Sendable inventory exists; ask is to extend it to a positive assertion ("entire Sendable surface auditable", not just "@unchecked surface enumerated"). Anchor `Sender.Send.swift:36` points to `immediate(...)` — the `Send` struct itself is at line 19; minor imprecision, claim still verifiable |
| 9 | @reviewer-c7 | The init/deinit/lifecycle reviewer (canonical c7) | 4 | load-bearing-candidate | **load-bearing** | act-on (claims verified): Sender ARC docstring exists, Ends asymmetry (stored receiver via _read/_modify vs synthesized sender via computed property) is real and worth type-level documentation; actor-deinit close path test coverage is a reasonable pre-1.0 ask |
| 10 | @reviewer-c6 | The Core-Team-aware process voice (canonical c6) | 9 | load-bearing-candidate | **load-bearing** | act-on (claims verified): README framing-vs-deferral observation echoes @c8 / @c10; cancelledCount public-vs-`package` is a contract decision worth one docstring sentence; Bridge example in README is a small ergonomic addition |
| 11 | @reviewer-c5 | The pointed -1 reviewer (canonical c5) | 6 | load-bearing-candidate | **load-bearing** | act-on (claims verified): the narrow -1 is on the Semantics §Cancellation-error stale-text finding (concrete, mechanical fix); Ends sender/receiver asymmetry observation echoes @c7 (independent-grep convergence); Broadcast.finish "silently ignored" framing decision is a documentation-shaped one-line addition |
| 12 | @op | OP follow-up | 9 | op-follow-up | op-follow-up | n/a — OP consolidation post |

## Anchor breakdown per post (auto-generated)

- Post 1 (@op): docc_catalog=1, backticked_fn=1, backticked_qualified=5, readme_ref=3 (total 10).
- Post 2 (@reviewer-c1): file_line=2, readme_ref=2 (total 4).
- Post 3 (@reviewer-c9): docc_catalog=1, file_line=5, backticked_fn=2, backticked_qualified=1 (total 9).
- Post 4 (@reviewer-c8): file_line=1, backticked_qualified=1, package_swift=2, readme_ref=4 (total 8).
- Post 5 (@reviewer-c10): docc_catalog=1, file_line=1, backticked_fn=1, readme_ref=2 (total 5).
- Post 6 (@reviewer-c3): file_line=1, backticked_fn=1, backticked_qualified=3 (total 5).
- Post 7 (@reviewer-c4): file_line=2, backticked_fn=1, backticked_qualified=4 (total 7).
- Post 8 (@reviewer-c2): file_line=2, backticked_qualified=1 (total 3).
- Post 9 (@reviewer-c7): file_line=4 (total 4).
- Post 10 (@reviewer-c6): file_line=2, backticked_type=1, backticked_qualified=1, readme_ref=5 (total 9).
- Post 11 (@reviewer-c5): docc_catalog=1, file_line=5 (total 6).
- Post 12 (@op): docc_catalog=1, backticked_fn=2, backticked_qualified=3, readme_ref=3 (total 9).

## Anchor verification per [FREVIEW-018]

Every load-bearing-classified post's anchor-grounded claims were source-verified against current state at HEAD `01c1c5e`. Summary of verification outcomes:

| Post | Verified claims | Issues found |
|------|-----------------|--------------|
| 2 (c1) | `Receive: Sendable` at Receiver.Receive.swift:17; `immediate` at Send.swift:36 | none — claims accurate; the "presumably the suspending variants" is a question, not a claim |
| 3 (c9) | Semantics.md Broadcast row text; §Cancellation-error block text; Completion.Error.swift:21 has `case cancelled`; Barrier.swift:225 typed-throws signature; Barrier.swift:195 `cancelledCount`; Bridge.swift:133 `next() async -> Element?`; Bridge.swift:136-141 single-consumer precondition; Sender.swift:24-39 ARC-Mediated docstring | none — all 8 anchor-grounded claims verified |
| 4 (c8) | README:60-69 Stability section text; Async_Primitives umbrella; Receive.swift:13 `#if !hasFeature(Embedded)` file-level gate | none — `Async_Primitives_Core` referenced as no-dep root verifies via Package.swift target listing |
| 5 (c10) | WithPermit.swift:39 `Either<Async.Semaphore.Error, E>` return type; Semantics §Cancellation-error block stale text | none — verified via independent grep |
| 6 (c3) | Mutex.swift four-branch cascade; Mutex.swift:27-32 fairness disclaimer; Mutex.swift:117-119 withLock signature; Barrier.swift:225 typed-throws; Barrier.swift:180 callback form; typed-throws audit reports zero in Sources/ | none — all anchors verified; the 18-vs-0 discrepancy is real and worth a footnote |
| 7 (c4) | Lifecycle.Error.swift non-generic enum; Semaphore.Error.swift:19 typealias; Completion.Error.swift:21 `case cancelled` | none — all verified |
| 8 (c2) | Sendable inventory exists with 5 unconditional `@unchecked`; Receiver.Receive.swift:17 checked Sendable | minor: anchor `Sender.Send.swift:36` points to `immediate()` not the `Send` struct (which is at line 19); claim still verifiable, position imprecision noted |
| 9 (c7) | Sender.swift:24-39 ARC-Mediated docstring; Ends.swift:47 sender computed property fresh-each-access; Ends.swift:20 `~Copyable, Sendable`; Ends.swift:37 receiver `_read`/`_modify`; Receiver.swift:154 `elements` AsyncSequence view | none — all 5 anchored claims verified |
| 10 (c6) | README:60-69; Bridge.swift:133 nonisolated(nonsending) next(); Barrier.swift:195 cancelledCount; Semantics.md doesn't currently distinguish contract vs diagnostic surface for cancelledCount | none — all verified |
| 11 (c5) | Mutex.swift four-branch cascade; Semantics.md §Cancellation-error stale; Completion.Error.swift:21; Ends.swift:47/37 asymmetry; Sender.swift:24-39 ARC docstring; Broadcast.swift:177 finish() + lines 173-176 docstring | none — all 7 anchored claims verified |

**No false-premise claims surfaced** in any load-bearing post. Every anchored claim resolves correctly against current source. The single load-bearing finding that appears across 4 independent-archetype posts (3, 5, 7, 11 — the c9 long-form, c10 heavy-quoting, c4 constructive Evolution-process, and c5 pointed -1) is the same Semantics.md §Cancellation-error stale-text inconsistency. Convergence across four archetype-shapes — a long-form essay reviewer, a heavy-quoting authoritative reviewer, a process-mechanic reviewer, and a -1 reviewer — is itself a correctness signal: this is not an archetype-shaped artifact (no single archetype's stereotyped voice produces this critique class); it's a real defect that anyone reading the package's primary contract artifact would surface.

## Calibration notes per [FREVIEW-017]

| Metric | Baseline (2026-04-24) | New (2026-04-25) | Threshold | Triggered? |
|--------|-----------------------|-------------------|-----------|------------|
| Reviewer posts | 10 | 10 | — | — |
| Pre-classified load-bearing-candidate | 10 | 10 | — | — |
| Final-classified load-bearing | 10 (1 via escape hatch on c2) | 10 (no escape hatch needed) | — | — |
| Reclassifications load-bearing → archetype-shaped | 0 | 0 | ≥ 3 | **No** |
| Top-5 angle ranking inversion | n/a | none — identical to baseline | inversion | **No** |
| False-premise claims | 0 (per baseline triage) | 0 | — | — |

No `[FREVIEW-017]` calibration trigger — neither the reclassification threshold nor the rank-inversion flag fires. The new simulation produces a comparable load-bearing surface to the 2026-04-24 baseline despite substantial mitigation work having landed, which is consistent with the characterizer's signals being unchanged (the work landed in documentation and packaging surfaces, not in the package-shape signals the characterizer scans). The substance of the load-bearing critiques has shifted: the 2026-04-24 critiques pointed at gaps that are now closed (Semantics article exists, Sendable inventory exists, Mutex portable, README versioning section exists, Lifecycle.Error consolidated); the 2026-04-25 critiques point at smaller, mostly documentation-shaped tightenings — *with one new headline finding* below.

## Headline new finding (load-bearing, surface to user before any implementation)

**`Sources/Async Primitives/Async Primitives.docc/Semantics.md` §Cancellation-error has stale text post commit `7e893ae`.**

The Semantics article's §Cancellation-error block (lines 61–85) contains two stale items:

1. Line 69: "`Async/Completion/Error` uses `.cancellation` (noun) — per-primitive enum, the lone outlier"
2. Lines 81–85: an entire paragraph framing the `.cancellation` → `.cancelled` rename as a "known pre-1.0 normalization target" still pending

Source state at HEAD `01c1c5e`: `Sources/Async Completion Primitives/Async.Completion.Error.swift:21` declares `case cancelled`. The rename landed at commit `7e893ae` ("Rename Async.Completion.Error.cancellation → .cancelled"); the Semantics article was not updated in the same commit. The article's own §Source of truth at line 102 states "When a primitive's behavior is clarified … update both the docstring at the source and this table in the same commit … treat [the doc/source drift] as a defect." The current state self-referentially meets the article's own definition of a defect.

Why load-bearing rather than archetype-shaped:

- Four independent archetype-voices (c9 long-form essay, c10 heavy-quoting authoritative, c4 constructive Evolution-process, c5 pointed -1) surface the same finding via independent paths in the simulation. No single archetype's stereotyped voice generates this critique class.
- The Semantics article is the package's most-cited doc artifact for naming-consistency arguments. Stale content there is a different category of defect from "this primitive's contract isn't documented" — it's "the documentation contradicts the source."
- The fix is mechanical (single-paragraph edit + line-69 spelling fix) but the supervisor ground rules forbid editing source/docs as part of this measurement task. The finding is surfaced, not actioned.

**Disposition** per the supervisor MUST entry "MUST surface any newly-emerged load-bearing critiques to the user before starting implementation": flagged in the delta-analysis doc and at the end of this triage; not actioned in this measurement task.

## Convergence with prior triage

| 2026-04-24 finding | 2026-04-25 status |
|--------------------|---------------------|
| Semantics article missing → angle #3 deflation gate | **Closed** (article exists; covers all 11 coordination primitives; no `gap` cells) |
| Mutex Darwin-only → narrow -1 target on c5 | **Closed** (four-branch portable cascade in Mutex.swift) |
| Sendable inventory missing → c2 escape hatch | **Closed** (Research/sendable-conformance-inventory.md enumerates 5 unconditional `@unchecked` sites) |
| README versioning posture missing → c8 / c6 question | **Partially closed** (README §Stability and versioning exists; the framing is candidly "pending resolution at the swift-institute level"; reviewers in 2026-04-25 sim ask for committal-rather-than-deferred framing) |
| swift-async-algorithms positioning missing | **Closed** (README §When to use this package) |
| Per-primitive cancellation-error consistency | **Source closed, docs partially stale** — the rename happened, the Semantics article wasn't updated. This is the headline new finding above. |
| 12 untyped throws claim | **False-premise in baseline** — 2026-04-24 audit at `Research/typed-throws-audit-2026-04-24.md` reports 0 untyped throws in `Sources/`; the characterizer's count includes test signatures and macro expansions. The audit's footnote disambiguating the count is itself a residual ask in the new simulation. |
| Async.Lifecycle.Error consolidation | **Closed** (non-generic enum at Async.Lifecycle.Error.swift; cases shutdown/cancelled/timeout) |
| withPermit typed-throws | **Closed** (returns `Either<Async.Semaphore.Error, E>` per WithPermit.swift:39) |
| Barrier cancellation-release path | **Closed** via Shape A (Barrier.swift:225 `arrive() async throws(Async.Lifecycle.Error)` with effective-party adaptation) |

The convergence column is the actual delta-measurement: **9 of the 10 baseline findings are closed; 1 is partially closed (versioning framing); and 1 new finding emerged (Semantics §Cancellation-error stale text)**. Of the 9 closed findings, the addressing work is concrete enough that the new simulation's archetypes engage with it positively rather than re-asking the original question.
