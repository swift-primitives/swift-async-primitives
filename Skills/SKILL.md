---
name: async-primitives
description: |
  Async/await primitives for concurrent programming.
  ALWAYS apply when working with async operations.

layer: implementation

requires:
  - primitives

applies_to:
  - swift
  - swift-primitives
  - swift-async-primitives
---

# Async Primitives

Async/await infrastructure primitives.

---

## Core Design Decisions

### [ASY-001] Architectural Layering

**Statement**: Async primitives MUST layer cleanly above kernel primitives.

---

## Cross-References

Full analysis: `Research/Architectural Analysis.md`
