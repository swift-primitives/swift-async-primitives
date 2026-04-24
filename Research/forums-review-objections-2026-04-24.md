---
package: swift-async-primitives
path: /Users/coen/Developer/swift-primitives/swift-async-primitives
predicted_date: 2026-04-24
mode: objection-prediction
predicted_category: related-projects
skill_version: v1.2 (FREVIEW-001..017)
venue_base_rates: stratified:related-projects (n=224)
era_correction: swift6-era (per-angle multipliers applied)
terminal_posture: not detected
corpus_state: full (602 threads, 25,428 posts, 11,674 substantive)
---

# [Predicted] Hardest-landing objections for `swift-async-primitives`

Scoring: `angle_score = venue_stratified_base_pct × era_multiplier × package_weight`. Full ranking in `forums-review-simulation-2026-04-24.json`.

All top-5 scored above 48 (vs top-score 44 for swift-carrier-primitives) — this is a denser critique surface than carrier, which reflects the package's size (109 files vs 26) and the weight-earning features (15 targets, 157 `~Copyable` types, 116 Sendable conformances, compound-identifier smells, Darwin-gated subtarget).

---

## 1. Layering / modularity / package boundaries — score 78.7

**Weight triggers**: 15 targets + 14 products (`× 1.5` for target_count > 10), L1 scrutiny (`× 1.3`), era × 1.17.

**Why it will land hardest of all**: this package makes a 14-product SemVer commitment that's uncommon enough in the ecosystem that every reviewer will ask about it. Two sub-threads, both load-bearing:

- **14-product granularity as contract**: is each product independently SemVer-ed, or does v1.0 commit the whole superrepo simultaneously? Both answers defensible; silence is not.
- **Embedded gating posture**: `#if !hasFeature(Embedded)` at source-file level produces empty modules on embedded, rather than manifest-level exclusion. Surprising shape.

**Mitigation (pre-1.0)**: explicit README section "Stability and versioning" stating which SemVer model applies. If all-14-products-together, commit to it. If per-product, add per-product tags (even if SwiftPM ignores them) so downstreams can reason about stability per module.

---

## 2. Naming / API surface naming — score 61.8

**Weight triggers**: L1 (`× 1.3`), compound-identifier smells detected (5 instances → `× 1.7` bump compounds with L1 → effective `× 2.21`), era × 0.98.

**Predicted critiques**:
- Method `immediate` on `Receiver` (`Async.Channel.Bounded.Receiver.Receive.swift:33`) reads as a property, not a method. Canonical Swift ergonomics would prefer `.receive(.immediate)` with an options-shape argument.
- Compound identifier smells — a grep for public types with embedded-CamelCase (2+ internal boundaries) surfaced 5. Each is a potential `-1 on naming` site.
- `os_unfair_lock`-backed `Async.Mutex` is unfair-by-default; the name doesn't signal this. Reviewers will compare to Rust's `parking_lot::Mutex` convention of flagging unfairness explicitly.

**Mitigation (pre-1.0)**: audit the 5 compound-identifier sites, re-decompose into nested namespaces where possible; adopt `.Options` convention for receive-mode selection; add fairness disclaimer to Mutex docstring.

---

## 3. Concurrency / isolation / Sendable — score 54.3

**Weight triggers**: `actor_decls > 0` + `async_fns > 5` + `sendable_conformances > 10` all trip (`× 2.0` concurrency bump), era × 1.13.

**Predicted critiques**:
- Semantics table missing: cancellation observation, ordering, backpressure, fairness per primitive. Every docstring is slightly differently phrased. A top-level DocC article tabulating these across all 13 primitives would deflate this entire angle.
- Channel multi-sender ordering undocumented.
- Broadcast cursor-vs-cancellation window — documented in per-file docstrings but not surfaced at package level.
- `withTaskGroup` composition — do primitives observe cooperative cancellation correctly when the outer task group throws?

**Mitigation (pre-1.0)**: the "Semantics" DocC article with the angle-table is the single biggest deflation available for this package. Every sub-critique collapses into "this is answered by the Semantics article at §X." Filling in the table is also the quickest way to find genuine gaps — any cell that can't be filled is exactly the pre-1.0 work.

---

## 4. Ownership / memory safety — score 52.8

**Weight triggers**: 157 `~Copyable` types (`× 2.0`), 54 unsafe mentions > 5 (`× 1.3`), era `× 1.75`. Net multiplier 2.60 — the highest in the package.

**Predicted critiques**:
- ARC-mediated auto-close semantics on `Sender` — documented at the level of "each copy shares the underlying storage," but the ARC increment mechanics and the actor-captured-sender-deinit interactions aren't explicit. `[FREVIEW-012]` post 9 in the simulation flagged this.
- `@unchecked Sendable` audit: 116 Sendable conformances without a published inventory of which are checked / conditional / unchecked. A pre-1.0 Research note enumerating each `@unchecked` with justification deflates c2's entire line of critique.
- `_read` + `nonmutating _modify` pattern in Mutex — correct shape per the ecosystem's ownership conventions, but per-generic-context correctness (CopyPropagation interaction under release builds) worth a test.

**Mitigation (pre-1.0)**: `Research/sendable-conformance-inventory.md` enumerating every conformance and its checked/unchecked status with justification; expansion of Sender ARC docstring; a release-mode test of the Mutex `_read` path under concurrent access.

---

## 5. Error handling / typed throws — score 48.2

**Weight triggers**: `typed_throws > 0` (42 sites → `× 1.5`), era × 0.97. First package in the validation set where error-handling weight is NOT deflated to × 0.3 — here it's a genuine angle.

**Predicted critiques**:
- 12 untyped `throws` sites in source. Mostly deliberate (protocol-conformance-constrained) but merit an audit — if any are oversights, they're better caught pre-1.0.
- Per-primitive cancellation-error types — consistency across the 13 primitives. Is it `Async.Channel.Error.cancelled`, `Async.Broadcast.Error.cancelled`, `Async.Barrier.Error.cancelled` etc.? Or a single shared `Async.Error.cancelled`?
- Error-type documentation — each `throws(E)` declaration should explicitly document what triggers `E` in the caller-visible docstring, not just the error-type name.

**Mitigation (pre-1.0)**: grep audit of the 12 untyped-throws sites with disposition; decision document on per-primitive-error vs shared-Async-error; a pass over the 42 typed-throws docstrings to confirm each documents trigger conditions.

---

## Lower-ranked but named

- **Performance (30.3)**: no specific concerns raised. Benchmarks directory present; if competitive numbers against `swift-async-algorithms` exist, worth surfacing in README.
- **Type-system (28.8)**: PAT / generic-constraint questions will be secondary to concurrency/ownership for this package.
- **Evolution-process (27.8)**: deflated by era-multiplier from the 33.9% base. Will surface as the SemVer-across-products question, which is already captured under #1 (Layering).
- **Scope-motivation (25.3)**: the "swift-async-algorithms positioning" question. One README section deflates it.

---

## Portability blocker (not angle-ranked, but called out in triage)

`Async.Mutex` is gated Darwin-only (`#if !hasFeature(Embedded) && canImport(Darwin)`). The rest of the package is Linux/Windows-compatible (gated only on embedded). For a package advertising "Swift Embedded compatible" and positioned as ecosystem-level primitives, shipping a Darwin-only Mutex is a visible portability regression. Simulation post 11 (@reviewer-c5, pointed -1) flagged this as the narrow -1 target.

**Mitigation**: either add `pthread_mutex_t` (Linux) and `SRWLock` (Windows) implementations pre-1.0, rename narrowly to `Async.Darwin.Mutex`, or document the scope limitation explicitly in README. The current state is surprising rather than wrong; pre-1.0 is the right time to resolve.

---

## Launch-readiness assessment

**Not ready to announce in `related-projects` until**:

1. **Semantics DocC article** with the primitive × (cancellation / ordering / backpressure / fairness) table. Single biggest pre-launch lift; deflates angles #3 and #5 simultaneously.
2. **Versioning posture** stated explicitly in README (14-products-committed-together vs per-product). Deflates #1.
3. **`@unchecked Sendable` inventory** in `Research/`. Deflates the #4 sub-critique.
4. **Mutex portability resolution**. Deflates the targeted -1.
5. **`swift-async-algorithms` positioning** section in README (≤ 1 paragraph). Deflates scope-motivation.

Items 1 and 2 are the biggest lifts — both are gated DocC/README work, each probably a day of focused writing. Items 3, 4, 5 are each a few hours.

Estimated soak: **~1 week of documentation + portability work** before the package is announcement-ready at this critique density. The skill does not predict design changes are needed; every top-5 mitigation is documentation-shaped or a narrow platform-extension of existing implementation.

## Skill-level notes from this validation

Not carrier-primitives-like; every ranking path was exercised. Specifically:
- Concurrency weight `× 2.0` earned its weight (angle #3).
- Error-handling weight `× 1.5` (typed throws present) landed above the × 0.3 floor — first time that path was validated.
- Layering `× 1.5` (target_count > 10) compounded with L1 × 1.3 to produce the #1 score.
- Compound-identifier-smell `× 1.7` tripped for the first time; producer-visibly penalised the naming angle.
- Era multiplier `× 1.75` on ownership-memory compounded with the package's × 2.0 to produce a 2.60 net, yielding the 52.8 score at a 11.6% pooled base.

No `[FREVIEW-017]` calibration adjustment suggested from this single point — the rankings above are consistent with what a careful human reviewer would produce against the same source. A calibration pass should still run once the package is actually announced and an observed-reception record lands in `analysis/calibration/observed/`.
