# swift-async-primitives Insights

<!--
---
title: swift-async-primitives Insights
version: 1.0.0
last_updated: 2026-03-22
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

## Doc Comments Referencing SE-0420

**Date**: 2026-03-22

**Context**: After migrating 14 functions from `isolation:` parameters to `nonisolated(nonsending)`, the `Async.Callback` doc comments still reference SE-0420 in the `callAsFunction` section.

Update doc comments to reflect the `nonisolated(nonsending)` method pattern instead of the deprecated `isolation:` parameter pattern. The migration was validated with 208 passing tests (88 async-primitives + 120 dependencies).

**Applies to**: `Async.Callback.callAsFunction` doc comments
