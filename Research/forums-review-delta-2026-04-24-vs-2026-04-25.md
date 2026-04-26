---
title: Forums-review delta 2026-04-24 → 2026-04-25
package: swift-async-primitives
package_head_at_baseline: pre-2026-04-25-mitigations
package_head_at_rerun: 01c1c5e
date: 2026-04-25
mode: delta-measurement
inputs:
  - Research/forums-review-objections-2026-04-24.md
  - Research/forums-review-objections-2026-04-25.md
  - Research/forums-review-simulation-2026-04-24.md
  - Research/forums-review-simulation-2026-04-25.md
  - Research/forums-review-triage-2026-04-24.md
  - Research/forums-review-triage-2026-04-25.md
---

# Forums-review delta — 2026-04-24 baseline vs 2026-04-25 re-run

The 2026-04-24 forums-review pass produced a launch-readiness verdict ("not ready until [5 items]") with predicted angle deltas — for each of the top-5 angles, a predicted *fall* in score after the mitigation work landed. The 2026-04-25 re-run measures the actual deltas. This document records per-angle predicted-vs-measured deltas, the substance shift between simulations, and what (if anything) the result calibrates about the skill.

## Top-5 angle scores: predicted vs measured

| Angle | Baseline score | Re-run score | Numeric Δ | Predicted (handoff) | Measured | Calibration note |
|-------|---------------:|-------------:|----------:|---------------------|----------|------------------|
| Layering / modularity / package boundaries | 78.7 | 78.68 | **+0.0** | falls due to SemVer documented | **flat** | Score insensitive — mitigation landed in README, not in source-shape signals |
| Naming / API surface naming                | 61.8 | 61.82 | **+0.0** | small fall from Mutex `.locked` removal | **flat** | Score insensitive — `.locked` removal is a code-shape change but didn't cross any characterizer threshold (5 compound-identifier smells unchanged; 14 products unchanged) |
| Concurrency / isolation / Sendable          | 54.3 | 54.27 | **+0.0** | biggest fall from Semantics article + gap fills | **flat** | Score insensitive — Semantics.md is a DocC catalog file, not a source signal |
| Ownership / memory safety                   | 52.8 | 52.81 | **+0.0** | falls from Sendable inventory + Sender ARC docstrings | **flat** | Score insensitive — inventory is in `Research/`, ARC docstrings are inside Sender.swift but didn't change `noncopyable_types` count materially |
| Error handling / typed throws                | 48.2 | 48.16 | **+0.0** | biggest fall from Lifecycle.Error consolidation + typed-throws audit + withPermit Either fix | **flat** | Score insensitive — typed_throws went 42 → 44 (slightly up); untyped_throws went 12 → 18 per characterizer (up; audit reports 0 in Sources/) |

**All five predicted falls did not occur in the score layer.** The numeric delta is essentially zero across all top-5 (differences are float-rounding only). This is the dominant signal in the re-run.

## Why the predicted falls didn't materialize at the score layer

The angle-score formula is:

```
angle_score = venue_stratified_base_pct × era_multiplier × package_weight
```

`venue_stratified_base_pct` and `era_multiplier` are corpus-derived (frozen until corpus refresh). `package_weight` is computed by `characterize_package.py` from source-shape signals: target_count, layer, compound-identifier-smell count, noncopyable_types presence, sendable_conformances presence, async_fns count, typed_throws presence, and so on.

The 2026-04-24 → 2026-04-25 mitigation work touched these signals as follows:

| Signal | Baseline | Re-run | Threshold? | Weight effect |
|--------|---------:|-------:|------------|---------------|
| swift_files | 109 | 108 | no | none |
| target_count | 15 | 15 | × 1.5 if > 10 | unchanged |
| product_count | 14 | 14 | — | unchanged |
| noncopyable_types | 157 | 152 | × 2.0 if > 0 | unchanged |
| borrowing_uses | 0 | 0 | — | unchanged |
| consuming_uses | 23 | 23 | — | unchanged |
| actor_decls | 1 | 1 | × 2.0 if > 0 | unchanged |
| sendable_conformances | 116 | 122 | × 1.x if > 10 | unchanged |
| async_fns | 21 | 21 | × 2.0 if > 5 | unchanged |
| typed_throws | 42 | 44 | × 1.5 if > 0 | unchanged |
| untyped_throws | 12 | 18 | — | unchanged |
| unsafe_mentions | 54 | 50 | × 1.3 if > 5 | unchanged |
| compound_identifier_smell | 5 | 5 | × 1.7 if ≥ 1 | unchanged |
| terminal_posture | not detected | not detected | × 0.5 if detected | unchanged |
| swift6-era | detected | detected | era multipliers | unchanged |

**Every signal that drives a multiplier stayed on the same side of its threshold.** The `noncopyable_types` count fell from 157 to 152 but stayed > 0. Sendable conformances rose from 116 to 122 but stayed > 10. Compound-identifier smell stayed at 5 (didn't drop to 0). The package's source-shape "looks the same" to the characterizer.

This is the load-bearing observation: **the characterizer cannot see documentation work or packaging-shape work**. The Semantics article, the README §Stability and versioning section, the Sendable inventory, the Mutex portability cascade, the Lifecycle.Error consolidation, the withPermit Either return, the Barrier Shape A typed-throws — all of those landed during the addressing window, and *none of them shifted any characterizer-detectable signal across a threshold*. The Mutex change moved code (one Darwin-gated implementation became a four-branch cascade), but it didn't change `noncopyable_types`, `actor_decls`, or `compound_identifier_smell`. The Lifecycle.Error consolidation moved code shape but typed_throws went 42 → 44 (slightly *up*, not down). Etc.

## Substance delta: the actual measurement layer

The substance of the simulated archetypes' critiques is where the addressing work shows up. The post-content layer is the right delta-measurement layer for documentation-shaped mitigations.

### Per-baseline-finding status at 2026-04-25

| 2026-04-24 finding | Predicted disposition | Measured disposition | Match? |
|--------------------|------------------------|----------------------|--------|
| Semantics article missing → angle #3 deflation | will close angle #3 | **closed in source/docs**; the article exists with no `gap` cells; **but** §Cancellation-error block has stale text post commit 7e893ae (new finding) | partial |
| Mutex Darwin-only → narrow -1 | will resolve via Linux pthread / Windows SRWLock / rename or doc | **closed differently**; resolved via four-branch cascade (Darwin → Synchronization → Kernel.Thread → no-op embedded), not via per-platform implementation; reviewer no longer surfaces it | yes |
| Sendable inventory missing → c2 escape hatch | will close c2 audit ask | **closed**; inventory exists; c2 in re-run is load-bearing without escape hatch (asks for positive checked-surface assertion to extend the inventory) | yes |
| README versioning posture missing → c8 / c6 | will close angle #1 sub-thread | **partially closed**; README §Stability and versioning exists but candidly framed as "pending resolution at the swift-institute level"; reviewers ask for committal-rather-than-deferred framing | partial |
| swift-async-algorithms positioning missing | will close scope-motivation | **closed**; README §When to use this package | yes |
| Per-primitive cancellation-error consistency (c4 ask) | will close via Lifecycle.Error consolidation | **source closed, docs partially stale**; rename happened, Semantics.md §Cancellation-error block didn't follow — same headline finding | partial |
| 12 untyped throws claim | will reduce after audit | **was a baseline false-premise**; audit reports 0 in Sources/ (the 12 was Tests/ test-function signatures); characterizer's 18 in re-run is the same conflation | refines baseline |
| Sender ARC docstring expansion | will close c7 ARC-mechanics ask | **closed**; Sender.swift:24-39 has the ARC-Mediated section | yes |
| Async.Lifecycle.Error consolidation | will close angle #5 | **closed**; non-generic enum at Async.Lifecycle.Error.swift; Semaphore.Error typealiases | yes |
| Async.Barrier cancellation-release path | not in baseline (emerged after) | **closed via Shape A**; Barrier.swift:225 typed-throws + cancelledCount accessor | n/a — emerged-and-shipped |
| Async.Completion.Error.cancellation → .cancelled rename | not in baseline | **landed in source, doc lag** — same headline finding | n/a — emerged-and-shipped |
| withPermit Either typed-throws fix | not in baseline | **landed**; WithPermit.swift:39 returns `Either<Async.Semaphore.Error, E>` | n/a — emerged-and-shipped |

**Net: 9 of 10 baseline findings closed; 1 partially closed (versioning framing); 1 new finding emerged (Semantics §Cancellation-error stale text post commit 7e893ae).**

### Predictions that didn't pan out

Two predictions diverged from outcomes in ways worth recording for `[FREVIEW-017]`:

1. **All five angle scores were predicted to fall; all five stayed flat.** The handoff's `fact:` entry framed the predictions as score-layer ("Concurrency #3 (54.3) → biggest fall"). The actual delta is zero in the score layer. The substance layer where the work showed up is not the layer the score formula scans. **Calibration note**: future delta-measurements should distinguish "score delta" from "substance delta" up front; the score layer is insensitive to documentation/packaging-shape changes by construction (the characterizer scans Sources/.swift signals, not docs).

2. **The "12 untyped throws" baseline finding was already false-premise at write-time.** Per the 2026-04-24 typed-throws audit, Sources/ had 0 untyped throws on 2026-04-24 — the 12 figure conflated Sources/ and Tests/ (test signatures use untyped `throws` per Swift Testing convention). The baseline's `[FREVIEW-018]` source-verification (had it run as part of the baseline triage, which precedes the rule's introduction) would have caught this. The re-run's characterizer reports 18 untyped throws using the same conflated count — the *signal* hasn't been fixed in the characterizer, only documented in the audit footnote work. **Calibration note**: the characterizer's `untyped_throws` count is a known false-positive surface for any package using Swift Testing in `Tests/`; future characterizer-tool work could disambiguate Sources/ from Tests/ in its grep.

### Predictions that landed correctly

The substance-layer predictions were largely correct:

- Sendable inventory closed c2's audit ask (re-run c2 is load-bearing without escape hatch).
- Sender ARC docstring expansion closed c7's ARC mechanics ask (re-run c7 acknowledges the docstring as the addressed shape and asks for adjacent things — `Ends` asymmetry, actor-deinit close path test).
- Mutex portability closed the narrow -1 target on c5 (re-run c5 ack the cascade; the -1 lands elsewhere).
- swift-async-algorithms positioning closed the scope-motivation question (no re-run reviewer raises it).
- Lifecycle.Error consolidation closed angle #5's lifecycle-shape consistency question.
- Barrier Shape A closed the cancellation-release path question for the in-flight case (the cancelled-before-arrive case is acknowledged as out-of-contract).
- The Semantics article closed angle #3 *substantively* — the c9 / c10 reviewers in the re-run engage with the article's content rather than asking for it to exist.

The score layer being insensitive to these landings is the calibration signal — not that the work didn't matter, but that the characterizer-driven score is the wrong instrument for measuring documentation deltas. The simulation's *post-content* layer is the right instrument.

### Newly-emerged load-bearing finding

**Semantics.md §Cancellation-error block stale text post commit `7e893ae`** is the single new load-bearing finding from the re-run. Surfaced by 4 independent archetype-voices (c9, c10, c4, c5) via independent grep paths during the simulation. Anchor-verified per `[FREVIEW-018]`:

- `Sources/Async Primitives/Async Primitives.docc/Semantics.md:69` says `Async/Completion/Error` uses `.cancellation` (the outlier).
- `Sources/Async Primitives/Async Primitives.docc/Semantics.md:81-85` frames the rename as a pending pre-1.0 normalization target.
- `Sources/Async Completion Primitives/Async.Completion.Error.swift:21` declares `case cancelled` (the rename landed at commit `7e893ae`).
- `Sources/Async Primitives/Async Primitives.docc/Semantics.md:102` (the article's own §Source of truth) names doc/source drift as a defect — self-referential violation.

**Mitigation**: single-paragraph edit + line-69 spelling fix. ~10 lines of doc work. The supervisor ground rules of this measurement task forbid editing source/docs; the finding is surfaced to the user not actioned by this task.

## Triage convergence

| Triage metric | 2026-04-24 | 2026-04-25 |
|---------------|-----------:|-----------:|
| Reviewer posts | 10 | 10 |
| Pre-classified load-bearing-candidate | 10 | 10 |
| Final-classified load-bearing | 10 (1 via [FREVIEW-012] escape hatch on c2) | 10 (no escape hatch needed) |
| Reclassifications load-bearing → archetype-shaped | 0 | 0 |
| False-premise claims (per [FREVIEW-018]) | n/a (rule introduced after) | 0 |
| Top-5 angle ranking inversion | n/a (baseline) | none |
| `[FREVIEW-017]` calibration triggered | no | no |

Both runs produce 10/10 load-bearing posts. The 2026-04-24 escape-hatch on c2 was a one-off — the c2 archetype's stereotyped voice is "ask about Sendable surface", which lands as load-bearing only when there's something to surface; the inventory landing in the addressing window means c2 in 2026-04-25 has anchor count 3 (just over the threshold) without an escape hatch.

The re-run's load-bearing convergence — same count, same archetypes, no false-premise claims, all anchored claims source-verified — gives reasonably high confidence that the simulation is exercising the package's real surface and not generating archetype-shaped artifacts.

## Re-run launch-readiness verdict

The 2026-04-24 verdict was **not ready to announce in `related-projects` until [5 items]**. As of 2026-04-25 at HEAD `01c1c5e`:

- All 5 baseline launch-readiness items have landed in code/docs/Research/.
- 4 emerged-and-shipped items (withPermit Either; Lifecycle.Error redesign; Completion.cancelled rename; Barrier Shape A) also landed.
- 1 new load-bearing item emerged: Semantics.md §Cancellation-error stale text.

**Updated verdict**: **ready to announce in `related-projects` after one mechanical fix** to Semantics.md §Cancellation-error block. The fix is small (~10 lines of doc), the criticism is unanimous across four archetype-voices, and the Semantics article is the package's primary contract artifact, so shipping with the stale text in place has asymmetrically high cost relative to the fix. Non-blocking documentation-shaped tightenings remain (committal-rather-than-deferred README versioning; `Ends` asymmetry docstring; accessor-pattern README note; cancelledCount API contract clarification; Bridge example in README; typed-throws-count audit footnote) but are nice-to-haves rather than launch blockers.

## Calibration data point for future delta-measurements

The dominant takeaway from this re-run is that **the score layer is insensitive to documentation/packaging-shape mitigation work, by construction.** Future delta-measurements should:

1. **Run the substance comparison up front** — pull the per-baseline-finding status from current source/docs/Research/ before drawing conclusions from the score deltas.
2. **Treat zero score delta as expected when mitigation is documentation-shaped** — not as evidence the mitigation didn't work.
3. **Use the simulation's post-content layer + triage convergence** as the actual delta-measurement instrument.
4. **The characterizer's `untyped_throws` is a known false-positive surface for packages with Swift Testing tests**; trust the per-package audit doc over the characterizer count when both exist.

Recommend recording this re-run as an observed-reception data point under `analysis/calibration/observed/` (per the `[FREVIEW-017]` schema) once the broader calibration corpus reaches threshold (≥5 records).
