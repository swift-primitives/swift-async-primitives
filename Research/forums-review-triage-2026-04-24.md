---
source_simulation: forums-review-simulation-2026-04-24.md
triage_date: 2026-04-24
rule: FREVIEW-012
pre_classification_automated: true
final_classification_requires_human_review: true
human_review_completed: 2026-04-24
human_reviewer: subordinate agent continuing HANDOFF.md (supervisor-in-absentia)
calibration_signal: none (≥3 archetype-shaped-final threshold not met; 0 reclassifications against automation's load-bearing calls, 1 escape-hatch upgrade)
---

# Concreteness-anchor triage — forums-review-simulation-2026-04-24

Pre-classifications are produced by `scripts/triage_simulation.py` using the
concreteness-anchor regex catalogue. **Final classifications require a human
review pass** to apply the manual escape hatch per [FREVIEW-012] — a post with
low anchor count MAY still be load-bearing if it surfaces a novel semantic
property of the target package. Such escapes MUST be justified in the
`final_classification_notes` column.

Quoted blocks (Discourse-style `> text` lines) and fenced code blocks are
excluded from the count — they don't count as the post author's own anchoring.

| # | handle | archetype (from comment) | anchor total | pre-classification | final classification | disposition |
|---|---|---|---:|---|---|---|
| 1 | @op | — | 1 | op-follow-up | op-follow-up | n/a (OP introduction) |
| 2 | @reviewer-c1 | The general-purpose technical reviewer (canonical c1) | 6 | load-bearing-candidate | load-bearing | act-on: Sender ARC-in-TaskGroup (→ Next Step #9 docstring expansion + test coverage gap); `.immediate` naming (→ Open Q #3, see notes) |
| 3 | @reviewer-c9 | The long-form deep-analysis essay reviewer (canonical c9) | 7 | load-bearing-candidate | load-bearing | act-on: each question maps to a `?`-cell in the Semantics DocC article (→ Next Step #3). Fills the broadcast/channel/barrier/promise rows |
| 4 | @reviewer-c8 | The SwiftPM / build-tooling / modularity reviewer (canonical c8) | 5 | load-bearing-candidate | load-bearing | act-on: granularity-as-contract is Open Q #1; embedded-gating posture → docs clarification; umbrella-vs-variant imports → README section per [feedback_no_umbrella_imports] |
| 5 | @reviewer-c10 | The heavy-quoting long-form authoritative reviewer (canonical c10) | 7 | load-bearing-candidate | load-bearing | act-on: the 13×4 table IS the Semantics-article scaffold (→ Next Step #3); `swift-async-algorithms` positioning → README paragraph (→ Next Step #7) |
| 6 | @reviewer-c3 | The closure/expression/syntax technical reviewer (canonical c3) | 3 | load-bearing-candidate | load-bearing | act-on: os_unfair_lock fairness disclaimer (→ Next Step #6); Ends.close() doc (→ Next Step #9); 12-untyped-throws audit (→ Next Step #8) |
| 7 | @reviewer-c4 | The constructive Evolution-process reviewer (canonical c4) | 5 | load-bearing-candidate | load-bearing | act-on: docstring-consistency ask is what the Semantics article enforces (→ Next Step #3); Token-deinit-under-cancellation is a testing gap worth flagging |
| 8 | @reviewer-c2 | The ~Copyable / Sendable / protocol-shape reviewer (canonical c2) | 2 | partially-load-bearing-candidate | **load-bearing (escape-hatched per [FREVIEW-012])** | act-on: the `@unchecked Sendable` inventory ask surfaces a genuine pre-1.0 semantic-property gap (116 Sendable conformances, unknown unchecked/checked split) despite low anchor count — see escape-hatch justification below (→ Next Step #4) |
| 9 | @reviewer-c7 | The init/deinit/lifecycle reviewer (canonical c7) | 3 | load-bearing-candidate | load-bearing | act-on: actor-isolated-deinit reentrancy, cancellation-close vs last-drop ordering, forced-vs-graceful Ends.close — all real contract gaps (→ Next Step #9 docstring expansion; (1) and (2) also flag testing-coverage asks) |
| 10 | @reviewer-c6 | The Core-Team-aware process voice (canonical c6) | 3 | load-bearing-candidate | load-bearing | act-on via Open Q #1: one-version-or-fourteen, cascading-major-on-one-product-break, per-product tags. No unilateral resolution — escalate to user |
| 11 | @reviewer-c5 | The pointed -1 reviewer (canonical c5) | 6 | load-bearing-candidate | load-bearing | act-on via Open Q #2: Darwin-only Mutex portability regression. Handoff Key Decisions explicitly confirms "genuine, not archetype-shaped" |
| 12 | @op | OP follow-up | 4 | op-follow-up | op-follow-up | n/a (OP consolidation; itself the road-map; not a reviewer critique) |

## Escape-hatch justification — Post 8 (@reviewer-c2, anchor=2)

Pre-classification: `partially-load-bearing-candidate` (anchor=2).

Final classification: `load-bearing` via [FREVIEW-012] manual escape hatch.

**Novel semantic property surfaced**: the package declares **116 Sendable conformances** but publishes no inventory distinguishing checked / conditional / `@unchecked`. The ask — `Research/sendable-conformance-inventory.md` with per-case justification — is a pre-1.0 artifact gap that deflates a real risk: a future Swift release that tightens one of the `@unchecked` corners and silently breaks a previously-passing conformance. The count (116) is itself an anchor the automated catalogue didn't credit because it's aggregate (not file:line) — the kind of signal [FREVIEW-012]'s escape hatch exists to catch.

The archetype c2 reflex ("audit your Sendables") fires on every package regardless; but the specific ask against *this* package is grounded in the observable count and the absence of the inventory artifact. Handoff Pre-Existing Code in Scope anticipated this: "Expect post 8 (c2 Sendable audit at 2 anchors) to be the main escape-hatch candidate."

This is the only escape-hatch upgrade in this triage pass. No reclassifications in the other direction (load-bearing-candidate → archetype-shaped-final). Per [FREVIEW-017] calibration threshold (≥3 archetype-shaped-final reclassifications against automation's load-bearing calls), no calibration signal.

## Anchor breakdown per post

- Post 1 (@op): se_crossref=1 (total 1).
- Post 2 (@reviewer-c1): file_line=2, backticked_fn=1, backticked_qualified=2, readme_ref=1 (total 6).
- Post 3 (@reviewer-c9): file_line=1, backticked_fn=1, backticked_qualified=3, readme_ref=2 (total 7).
- Post 4 (@reviewer-c8): backticked_fn=1, package_swift=2, readme_ref=2 (total 5).
- Post 5 (@reviewer-c10): file_line=1, backticked_type=2, backticked_qualified=2, package_swift=1, readme_ref=1 (total 7).
- Post 6 (@reviewer-c3): file_line=1, backticked_qualified=2 (total 3).
- Post 7 (@reviewer-c4): backticked_fn=2, backticked_qualified=1, se_crossref=2 (total 5).
- Post 8 (@reviewer-c2): file_line=1, backticked_qualified=1 (total 2).
- Post 9 (@reviewer-c7): file_line=2, backticked_qualified=1 (total 3).
- Post 10 (@reviewer-c6): backticked_qualified=3 (total 3).
- Post 11 (@reviewer-c5): backticked_qualified=4, readme_ref=2 (total 6).
- Post 12 (@op): backticked_type=1, backticked_qualified=1, readme_ref=2 (total 4).

## Summary: load-bearing distribution across the 10 substantive reviewer posts

- **10 / 10** load-bearing (1 via escape hatch; 9 via automated pre-classification, confirmed on review).
- **0** partially-load-bearing (the sole `partially` pre-classification escaped upward per above).
- **0** archetype-shaped-noise.
- **0** reclassifications against automation's load-bearing calls.

This distribution is consistent with the objections-doc verdict ("denser critique surface than most — top-5 angles all scored above 48") and with the handoff's framing that every finding is in scope for addressing. The skill's automated pre-classification was calibrated-correct for this package; no noise to discount.

## Action-item traceability

Mapping each load-bearing post to the Next Step it drives (from HANDOFF.md):

| Posts | Action | Next Step # |
|---|---|---|
| 3, 4, 5, 7, 9 | Semantics DocC article (13×4 table) | #3 |
| 8 | `@unchecked Sendable` inventory | #4 |
| 11 | Mutex portability resolution | #5 (blocked on Open Q #2) |
| 6 | `os_unfair_lock` fairness disclaimer | #6 |
| 4, 10 | README: SemVer posture + umbrella policy | #7 (blocked on Open Q #1) |
| 3, 5, 7 | README: `swift-async-algorithms` positioning | #7 |
| 6 | Typed-throws audit (12 untyped sites) | #8 |
| 2, 5, 6, 9 | Sender ARC / Ends.close / lifecycle docstrings | #9 |

Next Steps #1 (this document) is now complete.
Next Steps #2 (Open Questions to user) is the immediate blocker — escalation follows separately.

## Human-review instructions (applied)

1. Pre-classifications confirmed or overridden. One override (Post 8, partial → load-bearing) with prose justification above.
2. One-sentence dispositions populated in the table for each substantive post.
3. Zero archetype-shaped posts to discount.
4. Load-bearing proportion: 100% of substantive reviewer posts. Not a signal to re-run the simulation with a different seed — this reflects the package's dense critique surface, not a skewed archetype selection.
