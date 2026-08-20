// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    import Synchronization

    extension Async.Channel.Typed.Rendezvous
    where Element: ~Copyable, Failure: Swift.Error & Sendable {
        @usableFromInline
        final class Storage: Sendable {
            @usableFromInline let mutex: Async.Mutex<State>

            @usableFromInline
            init() {
                mutex = Async.Mutex(State())
            }

            @inlinable
            func withLock<T: ~Copyable>(_ body: (inout sending State) -> sending T) -> sending T {
                mutex.withLock(body)
            }
        }
    }

#endif  // !hasFeature(Embedded)
