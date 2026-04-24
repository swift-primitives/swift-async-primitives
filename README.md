# Async Primitives

Swift Embedded compatible.

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
