// MARK: - inout Optional<~Copyable> Closure Capture for Slot-Free Channel Send
//
// Purpose: Verify that a non-escaping closure (Mutex.withLock) can thread an
//          `inout Element?` where `Element: ~Copyable & Sendable`, allowing
//          the state machine to move the element out of the Optional inside
//          the lock — eliminating the per-send Ownership.Slot heap allocation.
//
// Hypothesis: A custom `withLockAndElement(_ element: inout Element?, body:)`
//             method can forward the inout reference through the Mutex.withLock
//             closure. The body can move the element out (setting Optional to nil)
//             on deliver/buffer paths, and leave it on the suspend path.
//             The `sending` return type is satisfied because the moved element
//             is disconnected from the captured inout after nil-assignment.
//
// Context:
//   - Current channel design allocates Ownership.Slot (heap + 4 atomics) per send
//   - Slot exists solely to cross the withLock closure boundary for ~Copyable
//   - If inout Optional works, fast-path sends need zero heap allocs
//   - Slow-path (suspension) still needs Slot (element must be heap-accessible
//     across tasks), but Slot allocation can be deferred to slow path only
//   - See: HANDOFF-zero-copy-audit-post-restructure.md findings §2
//
// Compiler bug encountered: force-unwrap (`!`) on `var Optional<~Copyable>`
//   into a generic `consuming T` parameter crashes Swift 6.3 IRGen.
//   Minimal repro: `struct NC: ~Copyable {}; func f<T: ~Copyable>(_ v: consuming T) {}; var o: NC? = NC(); f(o!)`
//   Workaround: use `.take()!` instead of `!` throughout.
//
// Toolchain: Apple Swift version 6.3 (swiftlang-6.3.0.123.5 clang-2100.0.123.102)
// Platform: macOS 26.0 (arm64)
//
// Result: CONFIRMED — all 9 variants pass (V1-V9). Pattern works for both
//   concrete and generic element types, including concurrent sends.
//   Compiler bug found: `o!` on `var Optional<~Copyable>` into generic consuming
//   parameter crashes Swift 6.3 IRGen (Invalid bitcast, address space 64).
//   Workaround: `.take()!` instead of `!` throughout.
// Date: 2026-03-27

import Synchronization
import Ownership_Primitives

// ============================================================================
// MARK: - Infrastructure
// ============================================================================

struct Resource: ~Copyable, Sendable {
    let id: Int
    init(_ id: Int) { self.id = id; print("  Resource(\(id)) init") }
    deinit { print("  Resource(\(id)) deinit") }
}

enum Decision: ~Copyable, @unchecked Sendable {
    case delivered(Resource)
    case buffered
    case suspend(id: UInt64)
    case closed
}

struct State: ~Copyable, @unchecked Sendable {
    var hasReceiver: Bool = false
    var isFull: Bool = false
    var closed: Bool = false
    var bufferedIds: [Int] = []
    var nextId: UInt64 = 0

    mutating func trySend(_ element: inout Resource?) -> Decision {
        guard !closed else { return .closed }

        if hasReceiver {
            hasReceiver = false
            let el = element.take()!
            return .delivered(el)
        }

        if !isFull {
            let el = element.take()!
            bufferedIds.append(el.id)
            _ = consume el
            return .buffered
        }

        let id = nextId
        nextId &+= 1
        return .suspend(id: id)
    }
}

final class Storage: @unchecked Sendable {
    let mutex: Mutex<State>
    let deliverySlot: Ownership.Slot<Resource>

    init(_ state: consuming State) {
        self.mutex = Mutex(state)
        self.deliverySlot = Ownership.Slot()
    }

    func withLock<T: ~Copyable, E: Error>(
        _ body: (inout State) throws(E) -> sending T
    ) throws(E) -> sending T {
        try mutex.withLock { state throws(E) -> T in
            try body(&state)
        }
    }

    func withLockAndElement<T: ~Copyable, E: Error>(
        _ element: inout Resource?,
        _ body: (inout State, inout Resource?) throws(E) -> sending T
    ) throws(E) -> sending T {
        try mutex.withLock { (state: inout State) throws(E) -> T in
            try body(&state, &element)
        }
    }
}

// ============================================================================
// MARK: - V1: Deliver path — element moved out inside lock
// Hypothesis: inout Optional<~Copyable> passes through Mutex.withLock.
//             Element moved out on deliver path, Optional is nil after.
// Result: CONFIRMED
// ============================================================================

func testV1() {
    print("=== V1: Deliver path ===")
    let storage = Storage(State(hasReceiver: true))
    var opt: Resource? = Resource(1)

    let decision = storage.withLockAndElement(&opt) { state, element in
        state.trySend(&element)
    }

    assert(opt == nil)
    switch consume decision {
    case .delivered(let r):
        print("  Delivered id: \(r.id)")
        _ = consume r
    default:
        fatalError("expected delivered")
    }
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V2: Buffer path — element consumed inside lock
// Hypothesis: Element moved from Optional into buffer inside lock.
// Result: CONFIRMED
// ============================================================================

func testV2() {
    print("\n=== V2: Buffer path ===")
    let storage = Storage(State())
    var opt: Resource? = Resource(2)

    let decision = storage.withLockAndElement(&opt) { state, element in
        state.trySend(&element)
    }

    assert(opt == nil)
    switch consume decision {
    case .buffered:
        print("  Buffered")
    default:
        fatalError("expected buffered")
    }
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V3: Suspend path — element stays in Optional
// Hypothesis: On suspend, element is NOT moved out. Optional still has it.
//             Caller can then defer Slot allocation to slow path only.
// Result: CONFIRMED
// ============================================================================

func testV3() {
    print("\n=== V3: Suspend path — element stays in Optional ===")
    let storage = Storage(State(isFull: true))
    var opt: Resource? = Resource(3)

    let decision = storage.withLockAndElement(&opt) { state, element in
        state.trySend(&element)
    }

    assert(opt != nil, "Element should still be in Optional on suspend")
    switch consume decision {
    case .suspend(let id):
        print("  Suspend id: \(id), element still in Optional")
    default:
        fatalError("expected suspend")
    }

    // Defer Slot allocation to slow path
    // NOTE: .take()! workaround for Swift 6.3 IRGen crash with `opt!`
    let slot = Ownership.Slot(opt.take()!)
    let taken = slot.take()!
    print("  Deferred Slot, took id: \(taken.id)")
    _ = consume taken
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V4: Closed path — element cleaned up by Optional deinit
// Hypothesis: On closed, element stays in Optional. Cleanup via nil assignment.
// Result: CONFIRMED
// ============================================================================

func testV4() {
    print("\n=== V4: Closed path ===")
    let storage = Storage(State(closed: true))
    var opt: Resource? = Resource(4)

    let decision = storage.withLockAndElement(&opt) { state, element in
        state.trySend(&element)
    }

    assert(opt != nil)
    switch consume decision {
    case .closed:
        print("  Closed, element still in Optional")
    default:
        fatalError("expected closed")
    }

    opt = nil  // cleanup
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V5: Multiple sends — repeated inout pattern
// Hypothesis: Pattern works repeatedly without accumulation or leaks.
// Result: CONFIRMED
// ============================================================================

func testV5() {
    print("\n=== V5: Multiple sends ===")
    let storage = Storage(State())

    for i in 10..<15 {
        var opt: Resource? = Resource(i)
        let decision = storage.withLockAndElement(&opt) { state, element in
            state.trySend(&element)
        }
        assert(opt == nil)
        _ = consume decision
    }

    storage.withLock { state in
        print("  Buffer IDs: \(state.bufferedIds)")
        assert(state.bufferedIds == [10, 11, 12, 13, 14])
    }
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V6: Deliver with deliverySlot (full channel pattern)
// Hypothesis: Element flows: inout Optional → Decision enum → deliverySlot.
//             Matches actual channel send → deliver → receiver-takes pattern.
// Result: CONFIRMED
// ============================================================================

func testV6() {
    print("\n=== V6: Deliver with deliverySlot (channel pattern) ===")
    let storage = Storage(State(hasReceiver: true))
    var opt: Resource? = Resource(6)

    let decision = storage.withLockAndElement(&opt) { state, element in
        state.trySend(&element)
    }

    assert(opt == nil)
    switch consume decision {
    case .delivered(let r):
        storage.deliverySlot.store(__unchecked: r)
        let received = storage.deliverySlot.take()!
        print("  Receiver got id: \(received.id)")
        _ = consume received
    default:
        fatalError("expected delivered")
    }
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V7: Concurrent sends from multiple tasks
// Hypothesis: Each task has its own stack-local `var opt: Resource?`.
//             The Mutex serializes state access. No races.
// Result: CONFIRMED
// ============================================================================

func testV7() async {
    print("\n=== V7: Concurrent sends ===")
    let storage = Storage(State())

    await withTaskGroup(of: Void.self) { group in
        for i in 100..<110 {
            group.addTask {
                var opt: Resource? = Resource(i)
                let decision = storage.withLockAndElement(&opt) { state, element in
                    state.trySend(&element)
                }
                assert(opt == nil)
                _ = consume decision
            }
        }
    }

    storage.withLock { state in
        print("  Buffer size: \(state.bufferedIds.count)")
        assert(state.bufferedIds.count == 10)
    }
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V8: Full pattern — fast path (inout) + slow path (deferred Slot)
// Hypothesis: Complete send pattern — fast path avoids Slot, slow path defers it.
// Result: CONFIRMED
// ============================================================================

func testV8() {
    print("\n=== V8: Full pattern — fast + slow path ===")
    let storage = Storage(State())

    // Fast path: buffer (no Slot)
    do {
        var opt: Resource? = Resource(80)
        let decision = storage.withLockAndElement(&opt) { state, element in
            state.trySend(&element)
        }
        assert(opt == nil)
        switch consume decision {
        case .buffered: print("  Fast path: buffered (zero alloc)")
        default: fatalError()
        }
    }

    // Mark full
    storage.withLock { state in state.isFull = true }

    // Slow path: suspend → defer Slot
    do {
        var opt: Resource? = Resource(81)
        let decision = storage.withLockAndElement(&opt) { state, element in
            state.trySend(&element)
        }

        switch consume decision {
        case .suspend(let id):
            assert(opt != nil)
            // NOTE: .take()! workaround for Swift 6.3 IRGen crash
            let slot = Ownership.Slot(opt.take()!)
            print("  Slow path: suspend(id: \(id)), Slot deferred")
            let r = slot.take()!
            print("  Receiver took id: \(r.id)")
            _ = consume r
        default: fatalError()
        }
    }
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - V9: Generic withLockAndElement (parameterized over Element type)
// Hypothesis: The pattern generalizes — withLockAndElement can be generic
//             over the element type, not hardcoded to Resource.
// Result: CONFIRMED
// ============================================================================

final class GenericStorage<Element: ~Copyable & Sendable>: @unchecked Sendable {
    let mutex: Mutex<GenericState<Element>>

    init(_ state: consuming GenericState<Element>) {
        self.mutex = Mutex(state)
    }

    func withLockAndElement<T: ~Copyable, E: Error>(
        _ element: inout Element?,
        _ body: (inout GenericState<Element>, inout Element?) throws(E) -> sending T
    ) throws(E) -> sending T {
        try mutex.withLock { (state: inout GenericState<Element>) throws(E) -> T in
            try body(&state, &element)
        }
    }
}

struct GenericState<Element: ~Copyable & Sendable>: ~Copyable, @unchecked Sendable {
    var consumed: Bool = false

    mutating func trySend(_ element: inout Element?) -> Bool {
        guard !consumed else { return false }
        let _ = element.take()!
        consumed = true
        return true
    }
}

func testV9() {
    print("\n=== V9: Generic withLockAndElement ===")
    let storage = GenericStorage<Resource>(GenericState())
    var opt: Resource? = Resource(9)

    let sent = storage.withLockAndElement(&opt) { state, element in
        state.trySend(&element)
    }

    assert(sent == true)
    assert(opt == nil)
    print("  Generic pattern works")
    print("  CONFIRMED")
}

// ============================================================================
// MARK: - Entry Point
// ============================================================================

testV1()
testV2()
testV3()
testV4()
testV5()
testV6()
await testV7()
testV8()
testV9()

print("\n=== SUMMARY ===")
print("V1: Deliver path (element moved out via inout)          — see above")
print("V2: Buffer path (element consumed inside lock)          — see above")
print("V3: Suspend path (element stays in Optional)            — see above")
print("V4: Closed path (cleanup via nil)                       — see above")
print("V5: Multiple sends (repeated pattern)                   — see above")
print("V6: Deliver with deliverySlot (channel pattern)         — see above")
print("V7: Concurrent sends from multiple tasks                — see above")
print("V8: Full pattern (fast inout + slow deferred Slot)      — see above")
print("V9: Generic withLockAndElement                          — see above")
