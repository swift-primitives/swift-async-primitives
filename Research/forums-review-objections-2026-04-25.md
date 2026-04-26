---
package: swift-async-primitives
path: /Users/coen/Developer/swift-primitives/swift-async-primitives
predicted_date: 2026-04-25
mode: objection-prediction
predicted_category: related-projects
skill_version: v1.2 (FREVIEW-001..018)
venue_base_rates: stratified:related-projects (n=224)
era_correction: swift6-era (per-angle multipliers applied)
terminal_posture: not detected
corpus_state: full (602 threads, 25,428 posts, 11,674 substantive)
package_head: 01c1c5e
baseline_reference: Research/forums-review-objections-2026-04-24.md
---

# [Predicted] Hardest-landing objections for `swift-async-primitives`

Scoring: `angle_score = venue_stratified_base_pct × era_multiplier × package_weight`. Full ranking in `forums-review-simulation-2026-04-25.json`.

**The top-5 angle ranking is identical to the 2026-04-24 baseline** (Layering 78.7 → Naming 61.8 → Concurrency 54.3 → Ownership 52.8 → Error-handling 48.2). The package-shape signals the characterizer scans haven't crossed any thresholds — 14 products, L1, 5 compound-identifier smells, 152 `~Copyable` types, 122 Sendable conformances, 44 typed-throws sites, swift-6-era-detected — none of those changed materially in the addressing window. The numerical scores stayed the same because the addressing work was documentation and packaging-shape work, not code-shape work.

**The substance of the predicted critiques has shifted, however.** The 2026-04-24 critiques pointed at gaps that are now closed; the 2026-04-25 critiques are smaller, tighter, and mostly documentation-shaped. **One new critique class emerged** at the very top of the simulation thread: stale text in the package's primary contract artifact (Semantics.md). See §1 below.

---

## 1. Layering / modularity / package boundaries — score 78.7 (unchanged)

**Weight triggers** (unchanged): 15 targets + 14 products (`× 1.5` for target_count > 10), L1 scrutiny (`× 1.3`), era × 1.17.

**Why it still lands hardest of all**: 14-product SemVer commitment is uncommon enough that every reviewer asks. The 2026-04-24 simulation had two sub-threads: 14-product granularity, and embedded gating posture. The README §Stability and versioning section addresses the granularity — but candidly: it says "pending resolution at the swift-institute level" with an interim contract ("treat all 14 products as sharing a single package-level version tag"). The 2026-04-25 simulation's c8 / c10 / c6 reviewers all engage with the section but ask the same follow-up: framing it as "decided for v1.x" rather than "pending" tightens it from a deferral to a commitment.

**Predicted critiques (2026-04-25)**:
- README §Stability and versioning is candidly framed as "pending resolution at the swift-institute level"; reviewers will read this as deferred rather than decided. Shift to "v1.x: all 14 products treated as one tag. v2.0 may revisit at the institute-wide level" closes the loop.
- Embedded-gating posture: file-level `#if !hasFeature(Embedded)` (e.g., `Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.Receive.swift:13`) means an embedded consumer importing `Async_Channel_Primitives` gets a successful import of an empty module — surprising shape vs. manifest-level `condition: .when(platforms: [...])` which would fail-fast.
- Umbrella vs narrow-variant import is recommended in README "Importing" section, not enforced — no warning, deprecation marker, or `@_disfavoredOverload` on the umbrella to discourage reflex `import Async_Primitives`.

**Mitigation (pre-1.0)**: README framing tightening (mechanical, ~1 paragraph); a Research note on the embedded-gating posture decision (file-level intentional? worth a writeup) as it's a real design choice with downstream implications; consider whether umbrella-discouragement is documentation-only or whether a build-warning is feasible.

---

## 2. Naming / API surface naming — score 61.8 (unchanged)

**Weight triggers** (unchanged): L1 (`× 1.3`), 5 compound-identifier smells (`× 1.7` bump compounds with L1 → effective `× 2.21`), era × 0.98.

**Why it still lands**: the package has 240 public declarations across 11 coordination primitives + supporting namespaces; naming consistency is load-bearing for any package this dense. The 2026-04-24 simulation's c1 reviewer asked about `immediate` reading like a property; the 2026-04-25 simulation's c1 reviewer engages with the `.receive` / `.send` accessor pattern as the resolved shape and asks for one-sentence README documentation of it.

**Predicted critiques (2026-04-25)**:
- The `.receive` / `.send` accessor pattern (`Sources/Async Channel Primitives/Async.Channel.Bounded.Receiver.swift:126` exposes `var receive: Receive` as the operation accessor; `Receive` struct at `Async.Channel.Bounded.Receiver.Receive.swift:17` exposes `immediate()`) is discoverable only by reading source. Worth one README sentence documenting the pattern: "operations are reached through `.receive` / `.send` accessors that namespace the variants."
- `Async.Mutex` fairness is now explicitly documented at `Async.Mutex.swift:27-32`. No critique residual here.
- `Ends.sender` (synthesized fresh per access at `Ends.swift:47`) vs `Ends.receiver` (stored, `_read`/`_modify` at `Ends.swift:37`) asymmetry is real but undocumented at the type level; a one-line type-level docstring on `Ends` naming the asymmetry closes the foot-gun.

**Mitigation (pre-1.0)**: README accessor-pattern note (one sentence); `Ends` type-level docstring naming receiver/sender asymmetry; the 5 compound-identifier smell sites are unchanged from 2026-04-24 — the per-site decisions to either decompose or accept the smell were not undertaken in this addressing window.

---

## 3. Concurrency / isolation / Sendable — score 54.3 (unchanged)

**Weight triggers** (unchanged): `actor_decls > 0` + `async_fns > 5` + `sendable_conformances > 10` all trip (`× 2.0` concurrency bump), era × 1.13.

**Why it still lands**: this is a coordination-primitives package; concurrency is the central concern. The 2026-04-24 simulation's #3 critique was "Semantics table missing." The 2026-04-25 state has the table — `Sources/Async Primitives/Async Primitives.docc/Semantics.md` covers all 11 coordination primitives with no `gap` cells. **But the article has stale text post commit `7e893ae`** that the 2026-04-25 simulation surfaces as a load-bearing finding from four independent archetype-voices.

**Predicted critiques (2026-04-25)**:
- **NEW HEADLINE FINDING**: `Semantics.md` §Cancellation-error block (lines 61–85) names `Async/Completion/Error` as using `.cancellation` (the outlier). Source at `Sources/Async Completion Primitives/Async.Completion.Error.swift:21` declares `case cancelled`. The rename landed at commit `7e893ae` but the article wasn't updated. The article's own §Source of truth at line 102 says doc/source drift is a defect — the current state self-referentially meets that definition. Mechanical fix (single-paragraph edit + line-69 spelling), but high-visibility because the Semantics article is the package's primary contract artifact.
- `Async.Bridge.next()` single-consumer invariant at `Bridge.swift:136-141` traps via `precondition`. Is the trap a contract claim (callable on it) or enforcement-only? The article doesn't distinguish.
- `Async.Channel.Bounded` close-vs-pending-element ordering is documented as "Mutex-acquisition order" in the article's row, but the Sender ARC-driven auto-close path (`Sender.swift:24-39`) names the mechanism without the ordering claim. One sentence in the article connecting the two would close it.

**Mitigation (pre-1.0)**: §Cancellation-error block mechanical fix (must do — see §6 below); Bridge single-consumer trap pinning test; one-sentence ordering claim addition for Channel.Bounded close path. The article was the single-biggest 2026-04-24 mitigation; the 2026-04-25 work is tightening, not replacing.

---

## 4. Ownership / memory safety — score 52.8 (unchanged)

**Weight triggers** (unchanged): 152 `~Copyable` types (`× 2.0`), 50 unsafe mentions > 5 (`× 1.3`), era `× 1.75`. Net multiplier 2.60 — still the highest in the package.

**Why it still lands**: ownership is a swift-6-era-native concern that 152 `~Copyable` declarations earn out. The 2026-04-24 simulation's #4 critique was Sender ARC mechanics + Sendable inventory + Mutex `_read` correctness. The Sender ARC docstring expanded (lines 24-39 of `Sender.swift` now document the refcount mechanics explicitly). The Sendable inventory exists at `Research/sendable-conformance-inventory.md` (5 unconditional `@unchecked` sites enumerated). Mutex coroutine-form `.locked` was removed (Option C); the only access is now through `withLock(_:)` / `withLockIfAvailable(_:)` with the `(inout sending Value) throws(E) -> sending T` closure shape.

**Predicted critiques (2026-04-25)**:
- The Sendable inventory is positive (enumerates `@unchecked` sites with justifications) but doesn't explicitly address the checked side. `Async.Channel.Bounded.Receiver.Receive` at `Receive.swift:17` declares `public struct Receive: Sendable` — checked. The `storage` capture's Sendable status traces through composition, but the inventory doesn't say so explicitly. Extending the inventory to a positive assertion ("we know our entire Sendable surface, not just the @unchecked subset") closes the loop.
- `Ends` asymmetry (stored `~Copyable` Receiver vs synthesized Copyable Sender at `Ends.swift:37/47`) is intentional but undocumented; the c7 lifecycle reviewer surfaces this as a foot-gun for consumers wrapping `Ends` in `Mutex<Ends>`.
- Actor-isolated deinit close path on captured Sender (deinit fires on actor's executor) — contract is now documented (Sender.swift:24-39); test coverage is the residual ask.

**Mitigation (pre-1.0)**: extend `sendable-conformance-inventory.md` with a positive-assertion paragraph on checked-by-composition surface; `Ends` type-level docstring (also helps angle #2); test for actor-isolated deinit close path.

---

## 5. Error handling / typed throws — score 48.2 (unchanged)

**Weight triggers** (unchanged): `typed_throws > 0` (44 sites → `× 1.5`), era × 0.97.

**Why it still lands**: typed throws is a Swift-6-era differentiator and the package commits to it heavily. The 2026-04-24 simulation's #5 critique was 12 untyped throws + per-primitive cancellation-error consistency + error-type documentation. The audit at `Research/typed-throws-audit-2026-04-24.md` reports 0 untyped throws in `Sources/`; the characterizer's 18 are macro-expanded test signatures. `Async.Lifecycle.Error` consolidated (non-generic enum with `shutdown / cancelled / timeout`); `Async.Semaphore.Error` typealiases to it; `Async.Completion.Error.cancellation → .cancelled` rename landed.

**Predicted critiques (2026-04-25)**:
- The `.cancellation → .cancelled` rename is in source; the **Semantics article §Cancellation-error block didn't follow** (see §3 — same headline finding).
- The c4 constructive Evolution-process reviewer surfaces this as "the principle is correct; the rollout is partial" — meaning the principle (typealias to Lifecycle.Error only when all three cases apply) is well-documented, but its lone documented exception (Completion as "outlier") was rendered false by the rename.
- `Async.Semaphore.withPermit` returns `Either<Async.Semaphore.Error, E>` (`WithPermit.swift:39`) — typed-throws-preserving, no existential erasure. Consumer-site ergonomics ask: an example of `Either.left` / `Either.right` pattern-matching in the docstring.
- `Async.Semaphore.Token`'s deinit + cancellation + shutdown interaction order: implementation likely correct, contract under-specified.

**Mitigation (pre-1.0)**: same Semantics.md fix as §3 (single mechanical edit closes both); typed-throws-count footnote in the audit doc disambiguating characterizer (18) vs Sources/ (0); Token deinit+cancellation+shutdown interaction docstring; `withPermit` consumer-site example.

---

## 6. Headline new load-bearing finding (cuts across angles #3 and #5)

**`Sources/Async Primitives/Async Primitives.docc/Semantics.md` §Cancellation-error has stale text post commit `7e893ae`.**

The Semantics article's §Cancellation-error block (lines 61–85) contains:

1. **Line 69**: "`Async/Completion/Error` uses `.cancellation` (noun) — per-primitive enum, the lone outlier"
2. **Lines 81–85**: an entire paragraph framing the `.cancellation` → `.cancelled` rename as a "known pre-1.0 normalization target" still pending

Source state at HEAD `01c1c5e` per `Sources/Async Completion Primitives/Async.Completion.Error.swift:21`: `case cancelled`. The rename landed at commit `7e893ae` ("Rename Async.Completion.Error.cancellation → .cancelled"); the article was not updated in the same commit. The article's own §Source of truth at line 102 names doc/source drift as a defect — the current state self-referentially meets that definition.

**Why classified as load-bearing rather than archetype-shaped**:

- Surfaced by **four independent archetype-voices** in the simulation (c9 long-form essay, c10 heavy-quoting authoritative, c4 constructive Evolution-process, c5 pointed -1) via independent paths. No single archetype's stereotyped voice generates this critique class.
- The Semantics article is the package's most-cited doc artifact for naming-consistency arguments.
- The c5 reviewer's narrow -1 vote is anchored on this finding ("-1 on tagging 1.0 with the stale text in place").

**Mitigation**: single-paragraph edit + line-69 spelling fix. Mechanical, ~10 lines of doc work. Per the supervisor ground rules of this measurement task, the fix is surfaced and not actioned. **Recommend authoring as a follow-up commit before any 1.0 announcement push.**

---

## Lower-ranked but named (unchanged from baseline)

- **Performance (30.3)**: no specific concerns. Benchmarks present.
- **Type-system (28.8)**: PAT / generic-constraint questions secondary to concurrency/ownership.
- **Evolution-process (27.8)**: now SemVer-shaped (covered under #1).
- **Scope-motivation (25.3)**: closed by the README `swift-async-algorithms` positioning section.

---

## Launch-readiness assessment (updated)

The 2026-04-24 verdict was **not ready to announce in `related-projects` until [5 items]**. As of 2026-04-25:

| 2026-04-24 launch-readiness item | Status | Evidence |
|----------------------------------|--------|---------|
| 1. Semantics DocC article | **Landed** (with one fix below) | `Sources/Async Primitives/Async Primitives.docc/Semantics.md`, all 11 primitives covered, no `gap` cells |
| 2. Versioning posture in README | **Landed** (committal-rephrasing recommended) | `README.md:60-69` |
| 3. `@unchecked Sendable` inventory | **Landed** | `Research/sendable-conformance-inventory.md` |
| 4. Mutex portability resolution | **Landed** | `Sources/Async Mutex Primitives/Async.Mutex.swift` four-branch portable cascade |
| 5. `swift-async-algorithms` positioning | **Landed** | `README.md:5-34` "When to use this package" |

Plus the items the handoff names as emerged-and-shipped:

| Emerged-and-shipped item | Status | Evidence |
|--------------------------|--------|---------|
| `withPermit` typed-throws fix | **Landed** | `Sources/Async Semaphore Primitives/Async.Semaphore+WithPermit.swift:39` |
| `Async.Lifecycle.Error` redesign to non-generic Pool-style | **Landed** | `Sources/Async Primitives Core/Async.Lifecycle.Error.swift` |
| `Async.Completion.Error.cancellation → .cancelled` rename | **Landed in source, doc lag** | `Sources/Async Completion Primitives/Async.Completion.Error.swift:21` (source); Semantics.md §Cancellation-error stale (doc) |
| `Async.Barrier` Shape A typed-throws on `arrive()` | **Landed** | `Sources/Async Barrier Primitives/Async.Barrier.swift:225` |
| Shape B `~Copyable Party` handle pattern as Phase 2 experiment | **Landed (on-shelf)** | `Experiments/barrier-handle-ownership/` |

**New verdict**: ready to announce in `related-projects` after **one mechanical fix** — the Semantics.md §Cancellation-error stale-text update. The fix is small (single-paragraph edit + line-69 spelling), the criticism is unanimous across four archetype-voices, and the Semantics article is the package's primary contract artifact, so the cost of shipping with the stale text in place is asymmetrically high.

Smaller documentation-shaped tightenings remain (README versioning framing rephrasing; `Ends` asymmetry docstring; accessor-pattern README note; cancelledCount API contract clarification; Bridge example in README; typed-throws-count footnote) — all are nice-to-haves rather than blockers, in my read.

Estimated remaining work: **~half a day** of documentation work to land the headline fix and the smaller tightenings. The package design itself has stabilized; the remaining surface is purely documentation and framing.

---

## Skill-level notes from this re-run

- **Score deltas: zero.** All five top-5 angle scores are identical to 2026-04-24 (78.7 / 61.8 / 54.3 / 52.8 / 48.2 → 78.68 / 61.82 / 54.27 / 52.81 / 48.16; differences are float-rounding only). The characterizer's signals are stable across the addressing window because the work landed in documentation and packaging-shape (README, DocC, Research/), which the characterizer doesn't scan.
- **Substance shifted, scores didn't.** This is a useful calibration data point for `[FREVIEW-017]`: the simulation's *score* layer measures characterizer-detectable density of risk; the simulation's *post-content* layer is where landed mitigation work shows up. A delta-measurement should look at the post layer, not the score layer.
- **Calibration didn't trigger** ([FREVIEW-017] threshold = 3 archetype-shaped-final reclassifications; observed = 0). Same as baseline.
- **Rank inversion didn't occur** (the `ask:` escalation in the handoff). Same top-5 ordering. No need to escalate that ask.
- **Zero false-premise claims** in the new simulation per [FREVIEW-018] anchor verification. All anchored claims resolve correctly against current source.
- **One emerged load-bearing finding** (Semantics.md stale text), surfaced by four archetype-voices via independent grep paths. Convergence across archetype-shapes is itself a correctness signal.
