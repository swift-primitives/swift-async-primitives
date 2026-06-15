# Async Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-async-primitives/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-async-primitives/actions/workflows/ci.yml)

Raw async coordination primitives — `Channel` / `Broadcast` / `Semaphore` / `Mutex` / `Barrier` / `Promise` / `Bridge` / `Completion` / `Publication` — for the layer below `AsyncSequence`. They support `~Copyable` element types, use typed throws on fallible operations, and surface cancellation as an observable `Async.Lifecycle.Error.cancelled` rather than as `CancellationError`.

---

## When to use this package vs `swift-async-algorithms`

`swift-async-primitives` and Apple's [`swift-async-algorithms`](https://github.com/apple/swift-async-algorithms) occupy adjacent layers and are intended to compose, not compete:

- **`swift-async-algorithms`** ships operators over `AsyncSequence` (`zip`, `merge`, `throttle`, `debounce`, `chain`, `combineLatest`, …) plus the `AsyncChannel` / `AsyncStream` family for streaming pipelines. Reach for it when you want sequence-shaped transformations and broadcast/multicast in the `AsyncSequence` idiom.
- **`swift-async-primitives`** ships the raw coordination primitives a layer below `AsyncSequence` (lock + condition + admission). Reach for it when you need a coordination primitive below the sequence idiom, when your element type is non-`Copyable`, or when you want the cancellation contract surfaced as `Async.Lifecycle.Error.cancelled`.

The two surfaces overlap on the word "channel" but differ in semantics: `AsyncChannel` is unbuffered and multi-consumer, while this package's `Async.Channel.Bounded` / `.Unbounded` are single-receiver, support `~Copyable` elements, and expose per-primitive backpressure / ordering / fairness contracts (see the `Semantics` DocC article). Where surfaces overlap, pick by contract; where they don't, the two compose — wrap a primitive's output in an `AsyncSequence` and feed it through async-algorithms operators.

---

## Quick Start

`Async.Bridge` is the sync-to-async handoff primitive — producers push synchronously from any thread, a single consumer awaits on the async side:

```swift
import Async_Bridge_Primitives

let bridge = Async.Bridge<Int>()

// Producer: synchronous, never suspends.
bridge.push(42)
bridge.finish()  // signal no more elements

// Consumer: a single task drains until finish() and the buffer empties.
Task {
    while let value = await bridge.next() { _ = value /* process value */ }
}
```

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-async-primitives.git", branch: "main")
]
```

Import the narrow product you need — the smallest dependency is the recommended consumer pattern across the ecosystem; the `Async Primitives` umbrella re-exports everything for convenience:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Async Channel Primitives", package: "swift-async-primitives"),    // just the channel
        .product(name: "Async Semaphore Primitives", package: "swift-async-primitives"),   // just the semaphore
        // …or the umbrella: .product(name: "Async Primitives", package: "swift-async-primitives")
    ]
)
```

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the corresponding Linux / Windows toolchain). It depends only on Swift Institute primitives — no Foundation, no external runtimes.

---

## API conventions

Coordination primitives keep the **suspending** form at the top level and namespace the **non-suspending** variants under `.send` / `.receive` accessors:

- `try await sender.send(value)` suspends if the buffer is full; `try sender.send.immediate(value)` does not, throwing `.full` / `.closed` / `.cancelled` instead.
- `try await receiver.receive()` suspends if the buffer is empty; `try receiver.receive.immediate()` does not, throwing `.empty` / `.cancelled` (and returning `nil` once drained and closed).

The pattern keeps top-level type APIs narrow while making the variant forms discoverable through the accessor.

---

## Platform Support

| Platform         | CI  | Status       |
|------------------|-----|--------------|
| macOS 26         | Yes | Full support |
| Linux            | Yes | Full support |
| Windows          | Yes | Full support |
| iOS/tvOS/watchOS | —   | Supported    |
| Swift Embedded   | —   | Pending (nightly-toolchain follow-up) |

---

## Related Packages

- [`swift-queue-primitives`](https://github.com/swift-primitives/swift-queue-primitives) — the FIFO buffering behind the channel primitives.
- [`swift-kernel-primitives`](https://github.com/swift-primitives/swift-kernel-primitives) — the typed kernel synchronization the locks and conditions are built on.

---

## Community

<!-- BEGIN: discussion -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
