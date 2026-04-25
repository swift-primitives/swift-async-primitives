# Async Primitives

Swift Embedded compatible.

## When to use this package vs `swift-async-algorithms`

`swift-async-primitives` and Apple's [`swift-async-algorithms`](https://github.com/apple/swift-async-algorithms)
occupy adjacent layers and are intended to compose, not compete:

- **`swift-async-algorithms`** ships operators over `AsyncSequence` (`zip`,
  `merge`, `throttle`, `debounce`, `chain`, `combineLatest`, …) plus the
  `AsyncChannel` / `AsyncStream` family for streaming pipelines built on
  top of `AsyncSequence`. Reach for it when you want sequence-shaped
  transformations and broadcast/multicast in the `AsyncSequence` idiom.
- **`swift-async-primitives`** ships raw coordination primitives —
  `Channel.Bounded` / `Channel.Unbounded` / `Broadcast` / `Semaphore` /
  `Mutex` / `Barrier` / `Promise` / `Bridge` / `Completion` / `Publication`
  — designed to support `~Copyable` element types, typed throws on
  fallible operations, and explicit cancellation observation. Reach for
  it when you need a coordination primitive at a layer below
  `AsyncSequence` (lock + condition + admission), or when your element
  type is non-`Copyable`, or when you want the cancellation contract
  surfaced as `Async.Lifecycle.Error.cancelled` rather than as
  `CancellationError`.

The two surfaces overlap on the word "channel" but the semantics differ.
`AsyncChannel` is unbuffered and multi-consumer; this package's
`Async.Channel.Bounded` and `.Unbounded` are single-receiver, support
`~Copyable` elements, and expose per-primitive backpressure / ordering /
fairness contracts (see the `Semantics` DocC article in the umbrella
catalog). Where surfaces overlap, you can pick by which contract fits;
where they don't, the two packages compose — e.g., wrap a primitive's
output in an `AsyncSequence` and feed it through async-algorithms
operators.

## Dependencies

This package depends only on Swift Institute primitives:
`swift-buffer-primitives`, `swift-dictionary-primitives`,
`swift-queue-primitives`, `swift-handle-primitives`,
`swift-tagged-primitives`, `swift-kernel-primitives`,
`swift-ownership-primitives`, `swift-algebra-primitives`. No Foundation,
no external runtimes.

## Importing

Consumers should import the narrow product module they need:

```swift
import Async_Channel_Primitives    // just the channel primitive
import Async_Semaphore_Primitives  // just the semaphore
import Async_Mutex_Primitives      // just the mutex
```

The `Async_Primitives` umbrella product re-exports everything and is provided
for convenience, but importing a narrow variant expresses the smallest
dependency and is the recommended consumer pattern across the Swift Institute
ecosystem.

## Stability and versioning

SwiftPM versions apply at the Package.swift level: one tag covers all
14 library products simultaneously. The ecosystem-wide posture for
what a v1.0 tag commits to across those products — one package version
freezes every product, or per-product stability tracked by a separate
convention — is pending resolution at the swift-institute level and is
not yet decided. Until that lands, consumers should treat the 14
products as sharing a single package-level version tag and pin
accordingly.
