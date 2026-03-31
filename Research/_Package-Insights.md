# swift-async-primitives Insights

<!--
---
title: swift-async-primitives Insights
version: 1.0.0
last_updated: 2026-03-31
applies_to: [swift-async-primitives]
normative: false
---
-->

Design decisions, implementation patterns, and lessons learned specific to this package.

## Overview

This document captures insights that emerged during development of swift-async-primitives.
These are not API requirements — they are recorded decisions and patterns that inform
future work on this package.

**Document type**: Non-normative (recorded decisions, not requirements).

**Consolidation source**: Reflection entries tagged with `[package: swift-async-primitives]`.

---

## Slot-per-Send Overhead (2026-03-27)

**Date**: 2026-03-27

**Context**: The ~Copyable channel restructure replaced direct element capture in `withLock` closures with Slot-per-send staging (one `Ownership.Slot` heap allocation + two atomic CAS per send) due to the closure capture consumption limitation ([MEM-COPY-006] Category 6).

The Slot-per-send overhead on the fast path is non-zero: one class allocation per send. For high-throughput channels, this may be measurable. The overhead should be benchmarked against the pre-restructure direct element passing to quantify the cost and determine if optimization is warranted.

The end-state solution ([IMPL-070] coroutine Mutex) would eliminate the closure entirely, avoiding both the capture limitation and the Slot overhead. Until the coroutine Mutex is production-ready, the Slot approach is the correct implementation.

**Applies to**: Async.Channel.Bounded, Async.Channel.Unbounded, send/trySend hot paths
