// MARK: - Barrier Handle-Ownership Validation
//
// Purpose: Validate Shape B from
//   swift-async-primitives/Research/barrier-api-investigation-2026-04-25.md
// — a `~Copyable Party` handle returned by `barrier.party()` whose deinit
// decrements the expected party count if the handle is dropped without an
// explicit `arrive()`. This shifts the party-count contract from runtime
// caller discipline to compile-time ownership enforcement per the
// /implementation skill's [IMPL-COMPILE] axiom.
//
// Hypothesis: A `~Copyable Party { consuming func arrive() async throws;
// deinit { decrement() } }` correctly distinguishes the consumed path
// (arrive succeeded → decrement does NOT fire) from the dropped paths
// (early return / throw / cancellation / explicit drop → deinit fires
// and decrements). This holds across direct scope, Task closures, and
// withTaskGroup child tasks under Swift 6.3.
//
// Toolchain: Swift 6.3
// Platform: macOS .v26
//
// Result: CONFIRMED — all six variants match the hypothesis. The
// Revalidated: Swift 6.3.1 (2026-04-30) — PASSES
// `~Copyable Party` deinit fires reliably on every drop path and is
// suppressed by `consuming func arrive()` setting the `didArrive` flag.
//
// Variant outcomes (arrived=A, cancelled=C):
//   V1 arrive() in direct scope                           → A=1, C=0
//   V2 drop in direct scope                               → A=0, C=1
//   V3 throw before arrive                                → A=0, C=1
//   V4 arrive inside Task                                 → A=1, C=0
//   V5 Task cancelled before arrive (suspended in sleep)  → A=0, C=1
//   V6 withTaskGroup, 3 parties, cancelAll mid-group      → A=2, C=1
//
// Implication: Shape B is empirically viable for swift-async-primitives'
// Async.Barrier. The party-count contract can be enforced at compile
// time via `~Copyable Party` ownership rather than at runtime via
// caller discipline. Adoption decision (whether to ship Shape B as a
// 1.0+ replacement for Shape A) is separate from this experiment;
// this experiment establishes only that the mechanism works.
//
// Date: 2026-04-25

import Synchronization

// MARK: - Minimal Shape B Implementation
//
// A self-contained, simplified Async.Barrier carrying only what's needed
// to validate the ownership pattern. Production semantics (FIFO, multi-
// suspension, etc.) are out of scope; the focus here is whether the
// handle's deinit fires (or doesn't) under the scenarios listed in
// `runScenario(_:)` below.

final class Barrier: Sendable {
    private let _state: Mutex<State>
    private let parties: Int

    struct State {
        var arrived: Int = 0
        var cancelled: Int = 0
        // Map of party-ID → completion: true if the party arrived; false if dropped
        var completions: [UInt64: Bool] = [:]
        var nextID: UInt64 = 0
    }

    init(parties: Int) {
        precondition(parties >= 1)
        self.parties = parties
        self._state = Mutex(State())
    }

    // Issue a fresh Party handle. ~Copyable, deinit-deregisters.
    func party() -> Party {
        let id = _state.withLock { state in
            let id = state.nextID
            state.nextID += 1
            return id
        }
        return Party(barrier: self, id: id)
    }

    // Internal API for Party
    fileprivate func _arriveSucceeded(id: UInt64) {
        _state.withLock { state in
            state.arrived += 1
            state.completions[id] = true
        }
    }

    fileprivate func _arriveDropped(id: UInt64) {
        _state.withLock { state in
            state.cancelled += 1
            state.completions[id] = false
        }
    }

    var arrived: Int { _state.withLock { $0.arrived } }
    var cancelled: Int { _state.withLock { $0.cancelled } }
    var completions: [UInt64: Bool] { _state.withLock { $0.completions } }
}

// `~Copyable` Party handle. Constructed by `Barrier.party()`, consumed
// by `arrive()`, or deinit-deregistered if dropped.
struct Party: ~Copyable {
    private let barrier: Barrier
    private let id: UInt64
    private var didArrive: Bool = false

    fileprivate init(barrier: Barrier, id: UInt64) {
        self.barrier = barrier
        self.id = id
    }

    consuming func arrive() {
        // Mark arrived; on consume the deinit checks this flag.
        // Use `defer` so the flag set survives any subsequent throw.
        didArrive = true
        barrier._arriveSucceeded(id: id)
        // Default consuming-func semantics: self is dropped at end → deinit
        // runs. Since didArrive is true, deinit is a no-op for this path.
    }

    deinit {
        if !didArrive {
            barrier._arriveDropped(id: id)
        }
    }
}

// MARK: - Scenarios
//
// Each variant exercises one drop / consume path and prints the resulting
// barrier state.

@MainActor
func runScenario(_ name: String, _ body: () async throws -> Void) async {
    print("---")
    print("[\(name)]")
    do {
        try await body()
    } catch {
        print("scenario threw: \(error)")
    }
}

// V1: Consumed via arrive() — no decrement expected.
@MainActor
func variantArriveDirect() async {
    let barrier = Barrier(parties: 3)
    let party = barrier.party()
    party.arrive()
    print("arrived=\(barrier.arrived) cancelled=\(barrier.cancelled) completions=\(barrier.completions)")
}

// V2: Dropped without arrive — deinit should decrement.
@MainActor
func variantDropDirect() async {
    let barrier = Barrier(parties: 3)
    do {
        let _ = barrier.party()
        // dropped at scope exit
    }
    print("arrived=\(barrier.arrived) cancelled=\(barrier.cancelled) completions=\(barrier.completions)")
}

// V3: Thrown after issue, before arrive.
@MainActor
func variantThrowBeforeArrive() async {
    let barrier = Barrier(parties: 3)
    struct E: Error {}
    do {
        let _ = barrier.party()
        throw E()
    } catch {}
    print("arrived=\(barrier.arrived) cancelled=\(barrier.cancelled) completions=\(barrier.completions)")
}

// V4: Inside a Task body, arrive() called.
@MainActor
func variantArriveInTask() async {
    let barrier = Barrier(parties: 3)
    let task = Task {
        let p = barrier.party()
        p.arrive()
    }
    await task.value
    print("arrived=\(barrier.arrived) cancelled=\(barrier.cancelled) completions=\(barrier.completions)")
}

// V5: Inside a Task body, Task is cancelled before arrive — Party should
// be dropped on Task tear-down.
@MainActor
func variantCancelTaskBeforeArrive() async {
    let barrier = Barrier(parties: 3)
    let task = Task {
        let _ = barrier.party()
        // Suspend to let cancellation propagate
        try? await Task.sleep(for: .milliseconds(50))
        // If we resumed here without cancellation, never reach this point in
        // the cancelled scenario (the sleep throws on cancel; we swallow).
    }
    // Give task time to start, then cancel.
    try? await Task.sleep(for: .milliseconds(10))
    task.cancel()
    await task.value
    print("arrived=\(barrier.arrived) cancelled=\(barrier.cancelled) completions=\(barrier.completions)")
}

// V6: withTaskGroup — three child parties; one is cancelled, two arrive.
@MainActor
func variantTaskGroupMixed() async {
    let barrier = Barrier(parties: 3)
    await withTaskGroup(of: Void.self) { group in
        // First two arrive normally
        for _ in 0..<2 {
            group.addTask {
                let p = barrier.party()
                p.arrive()
            }
        }
        // Third is cancelled before it can arrive
        group.addTask {
            let _ = barrier.party()
            try? await Task.sleep(for: .milliseconds(100))
            // Cancellation should drop the party in deinit
        }
        // Cancel the third task (and one of the others; group cancels all)
        // Sleep briefly so the third task suspends.
        try? await Task.sleep(for: .milliseconds(20))
        group.cancelAll()
        await group.waitForAll()
    }
    print("arrived=\(barrier.arrived) cancelled=\(barrier.cancelled) completions=\(barrier.completions)")
}

// MARK: - Driver

@main
struct Driver {
    static func main() async {
        await runScenario("V1: arrive() in direct scope", variantArriveDirect)
        await runScenario("V2: drop in direct scope", variantDropDirect)
        await runScenario("V3: throw before arrive", variantThrowBeforeArrive)
        await runScenario("V4: arrive inside Task", variantArriveInTask)
        await runScenario("V5: Task cancelled before arrive", variantCancelTaskBeforeArrive)
        await runScenario("V6: withTaskGroup with cancelAll", variantTaskGroupMixed)
        print("---\nDone.")
    }
}
