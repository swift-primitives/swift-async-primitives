// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Async_Primitives_Test_Support
import Testing

#if canImport(Darwin)
    import Darwin
#endif

// MARK: - Helpers

/// Checks if the current thread is the main thread.
/// Uses Darwin `pthread_main_np()` — no Foundation dependency.
#if canImport(Darwin)
    private func isMainThread() -> Bool {
        pthread_main_np() != 0
    }
#endif

/// A non-Sendable reference type for testing `Value: ~Sendable` support.
private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Test Suites

/// Test namespace for Async.Callback (generic type requires wrapper per [TEST-004]).
enum Callback {
    enum Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
        @Suite struct Integration {}
        @Suite(.serialized) struct Performance {}
    }
}

// MARK: - Unit Tests

extension Callback.Test.Unit {
    @Test
    func `init with immediate value returns that value`() async {
        let callback = Async.Callback(value: 42)
        #expect(await callback() == 42)
    }

    @Test
    func `init with deferred computation produces value`() async {
        let callback = Async.Callback<String> { "computed" }
        #expect(await callback() == "computed")
    }

    @Test
    func `deferred computation does not execute until called`() async {
        var executed = false
        let callback = Async.Callback<Int> {
            executed = true
            return 99
        }
        #expect(!executed)
        let result = await callback()
        #expect(executed)
        #expect(result == 99)
    }

    @Test
    func `map transforms value`() async {
        let callback = Async.Callback(value: 21).map { $0 * 2 }
        #expect(await callback() == 42)
    }

    @Test
    func `map chains three levels`() async {
        let callback = Async.Callback(value: 10)
            .map { $0 + 5 }
            .map { "v=\($0)" }
            .map { $0.count }
        #expect(await callback() == 4)  // "v=15".count
    }

    @Test
    func `flatMap chains computations`() async {
        let callback = Async.Callback(value: 7)
            .flatMap { v in Async.Callback(value: "r=\(v * 6)") }
        #expect(await callback() == "r=42")
    }

    @Test
    func `flatMap chains multiple levels`() async {
        let callback = Async.Callback(value: 1)
            .flatMap { v in Async.Callback(value: v + 10) }
            .flatMap { v in Async.Callback(value: v * 2) }
        #expect(await callback() == 22)  // (1+10)*2
    }

    @Test
    func `non-Sendable value produced inside callback`() async {
        let callback = Async.Callback<Box<String>> { Box("hello") }
        let result = await callback()
        #expect(result.value == "hello")
    }

    @Test
    func `non-Sendable value through map`() async {
        let callback = Async.Callback<Box<Int>> { Box(21) }
            .map { "\($0.value * 2)" }
        #expect(await callback() == "42")
    }

    #if !hasFeature(Embedded)
        @Test
        func `init wrapping bridges CPS completion handler`() async {
            let callback = Async.Callback<Int>(wrapping: { completion in
                completion(42)
            })
            #expect(await callback() == 42)
        }
    #endif
}

// MARK: - Edge Cases

extension Callback.Test.EdgeCase {
    @Test
    func `Void callback completes without value`() async {
        var flag = false
        let callback = Async.Callback<Void> {
            flag = true
        }
        await callback()
        #expect(flag)
    }

    @Test
    func `nested callback flattened via flatMap`() async {
        let inner = Async.Callback(value: 42)
        let outer = Async.Callback(value: ()).flatMap { _ in inner }
        #expect(await outer() == 42)
    }

    @Test
    func `identity map preserves value`() async {
        let callback = Async.Callback(value: "unchanged").map { $0 }
        #expect(await callback() == "unchanged")
    }

    @Test
    func `multiple invocations produce independent results`() async {
        var counter = 0
        let callback = Async.Callback<Int> {
            counter += 1
            return counter
        }
        let first = await callback()
        let second = await callback()
        #expect(first == 1)
        #expect(second == 2)
    }

    @Test
    func `flatMap left identity — wrapping then chaining equals direct application`() async {
        let f: (Int) -> Async.Callback<String> = { v in .init(value: "n=\(v)") }
        let lhs = Async.Callback(value: 5).flatMap(f)
        let rhs = f(5)
        let lhsResult = await lhs()
        let rhsResult = await rhs()
        #expect(lhsResult == rhsResult)
    }

    @Test
    func `flatMap right identity — chaining with init(value:) is identity`() async {
        let callback = Async.Callback(value: 42)
        let chained = callback.flatMap { Async.Callback(value: $0) }
        let lhs = await chained()
        let rhs = await callback()
        #expect(lhs == rhs)
    }

    #if !hasFeature(Embedded)
        @Test
        func `CPS bridge with asynchronous completion`() async {
            let callback = Async.Callback<String>(wrapping: { completion in
                Task.detached {
                    completion("delayed")
                }
            })
            #expect(await callback() == "delayed")
        }
    #endif
}

// MARK: - Integration (Isolation)

#if canImport(Darwin)
    extension Callback.Test.Integration {
        @Test @MainActor
        func `init closure preserves MainActor isolation`() async {
            let callback = Async.Callback<Bool> { isMainThread() }
            #expect(await callback())
        }

        @Test @MainActor
        func `map transform preserves MainActor isolation`() async {
            let callback = Async.Callback(value: 21)
                .map { _ -> Bool in isMainThread() }
            #expect(await callback())
        }

        @Test @MainActor
        func `chained maps preserve isolation at each level`() async {
            let callback = Async.Callback(value: 0)
                .map { _ -> Bool in isMainThread() }
                .map { level1 -> (Bool, Bool) in (level1, isMainThread()) }
            let (level1, level2) = await callback()
            #expect(level1)
            #expect(level2)
        }

        @Test @MainActor
        func `flatMap preserves isolation`() async {
            let callback = Async.Callback(value: 0)
                .flatMap { _ in Async.Callback(value: isMainThread()) }
            #expect(await callback())
        }

        @Test @MainActor
        func `caller remains on MainActor after awaiting callback`() async {
            let callback = Async.Callback(value: 42)
            let result = await callback()
            #expect(result == 42)
            #expect(isMainThread())
        }

        #if !hasFeature(Embedded)
            @Test @MainActor
            func `CPS bridge returns to caller isolation`() async {
                let callback = Async.Callback<Int>(wrapping: { completion in
                    completion(42)
                })
                let result = await callback()
                #expect(result == 42)
                #expect(isMainThread())
            }
        #endif
    }
#endif
