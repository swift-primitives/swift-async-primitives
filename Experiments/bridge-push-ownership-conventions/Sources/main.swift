// MARK: - Bridge.push() Ownership Convention Experiment
//
// Purpose: Determine which ownership conventions for ~Copyable parameters
//   trigger the "missing reinitialization of closure capture after consume"
//   error inside Mutex.withLock closures.
//
// Hypothesis: The closure capture reinitialization error is caused by `consuming`
//   on the parameter, regardless of `sending`. For ~Copyable types, `consuming`
//   is mandatory (sending alone is not an ownership specifier).
//
// Toolchain: Apple Swift version 6.3 (swiftlang-6.3.0.123.5 clang-2100.0.123.102)
// Status: SUPERSEDED 2026-04-30 — Closure-capture ownership rule for ~Copyable elements tightened in Swift 6.3 — missing reinitialization after consume now diagnosed; experiment patterns require re-targeting
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL PRESENT (deep API drift; SUPERSEDED per [META-007])
// Platform: macOS 26.0 (arm64)
//
// Result: REFUTED — `consuming` is mandatory for ~Copyable. The reinitialization
//   error is fundamental: Mutex.withLock closures CANNOT consume captured
//   ~Copyable values, even on a single unconditional path (V3). This is a
//   Swift compiler limitation, not an annotation choice issue.
//
//   V1 (consuming):          FAILS — reinitialization error (guard + consume)
//   V2 (consuming sending):  FAILS — same error (sending doesn't change it)
//   V3 (consuming, 1 path):  FAILS — same error (NO BRANCHING, still fails)
//   V4 (consuming, if/else): FAILS — same error (both branches consume)
//   V5 (consuming, switch):  FAILS — same error (both cases consume)
//   V6 (borrowing):          COMPILES — no consume in closure, but can't transfer ownership
//   V7 (inout Element?):     FAILS — `if var e = element` counts as consume
//
//   Prior build: `sending` alone rejected ("must specify ownership"),
//   `sending consuming` rejected ("sending must be placed after consuming").
//
//   Conclusion: Optional wrapper + .take()! is not a workaround — it's the
//   only way to move a ~Copyable value into Mutex-protected storage in Swift 6.3.
//   Worth filing against swiftlang/swift.
// Date: 2026-03-31

import Synchronization

// ============================================================================
// MARK: - Infrastructure
// ============================================================================

struct Resource: ~Copyable, Sendable {
    let id: Int
    init(_ id: Int) { self.id = id }
    deinit { print("  Resource(\(id)) deinit") }
}

struct State: ~Copyable {
    var buffer: [Int] = []
    var isFinished: Bool = false

    mutating func push(_ element: consuming Resource) {
        buffer.append(element.id)
    }
}

// ============================================================================
// MARK: - V1: consuming only — guard + consume on both paths
//
// Hypothesis: `consuming` without `sending` triggers the same error.
// Result: (pending)
// ============================================================================

func pushV1(_ element: consuming Resource) {
    let mutex = Mutex(State())
    let _ = mutex.withLock { state in
        guard !state.isFinished else {
            _ = consume element
            return false
        }
        state.push(element)
        return true
    }
}

// ============================================================================
// MARK: - V2: consuming sending — the current Bridge pattern
//
// Hypothesis: Adding `sending` doesn't change the reinitialization behavior.
// Result: (pending)
// ============================================================================

func pushV2(_ element: consuming sending Resource) {
    let mutex = Mutex(State())
    let _ = mutex.withLock { state in
        guard !state.isFinished else {
            _ = consume element
            return false
        }
        state.push(element)
        return true
    }
}

// ============================================================================
// MARK: - V3: consuming — single path (no guard, no branching)
//
// Hypothesis: The error only appears with branching control flow.
//   If the closure has a single path that always consumes, it may work.
// Result: (pending)
// ============================================================================

func pushV3(_ element: consuming Resource) {
    let mutex = Mutex(State())
    let _ = mutex.withLock { state in
        state.push(element)
        return true
    }
}

// ============================================================================
// MARK: - V4: consuming — if/else (both branches consume)
//
// Hypothesis: if/else where both branches explicitly consume may satisfy
//   the compiler (vs guard which has an implicit fallthrough).
// Result: (pending)
// ============================================================================

func pushV4(_ element: consuming Resource) {
    let mutex = Mutex(State())
    let _: Bool = mutex.withLock { state in
        if state.isFinished {
            _ = consume element
            return false
        } else {
            state.push(element)
            return true
        }
    }
}

// ============================================================================
// MARK: - V5: consuming — using noncopyable switch pattern
//
// Hypothesis: A switch with explicit consume on all cases may work.
// Result: (pending)
// ============================================================================

func pushV5(_ element: consuming Resource) {
    let mutex = Mutex(State())
    let _: Bool = mutex.withLock { state in
        switch state.isFinished {
        case true:
            _ = consume element
            return false
        case false:
            state.push(element)
            return true
        }
    }
}

// ============================================================================
// MARK: - V6: borrowing — copy what we need, never consume in closure
//
// Hypothesis: If we only borrow the element and extract what we need
//   (for Copyable payloads like id: Int), we avoid consume entirely.
//   Only works if Element's useful payload is Copyable.
// Result: (pending)
// ============================================================================

func pushV6(_ element: borrowing Resource) {
    let id = element.id  // extract Copyable payload before lock
    let mutex = Mutex(State())
    let _ = mutex.withLock { state in
        guard !state.isFinished else { return false }
        state.buffer.append(id)
        return true
    }
    // element is dropped here (borrowing — caller retains ownership,
    // but for our test the caller passes a temporary)
}

// ============================================================================
// MARK: - V7: inout Element? — reference-based, no ownership in closure
//
// Hypothesis: If the caller owns the Optional and push takes inout,
//   the closure captures a reference, not an owned value. No consume needed.
// Result: (pending)
// ============================================================================

func pushV7(_ element: inout Resource?) {
    let mutex = Mutex(State())
    let _ = mutex.withLock { state in
        guard !state.isFinished else {
            element = nil
            return false
        }
        if var e = element {
            element = nil
            state.push(e)
        }
        return true
    }
}

// ============================================================================
// MARK: - Entry Point
// ============================================================================

print("=== V1: consuming only ===")
pushV1(Resource(1))

print("\n=== V2: consuming sending ===")
pushV2(Resource(2))

print("\n=== V3: consuming, single path ===")
pushV3(Resource(3))

print("\n=== V4: consuming, if/else ===")
pushV4(Resource(4))

print("\n=== V5: consuming, switch ===")
pushV5(Resource(5))

print("\n=== V6: borrowing (extract payload) ===")
pushV6(Resource(6))

print("\n=== V7: inout Element? ===")
var slot7: Resource? = Resource(7)
pushV7(&slot7)

print("\n=== Prior findings (from first build attempt) ===")
print("- `sending` alone: NOT an ownership specifier — ~Copyable requires consuming/borrowing/inout")
print("- `sending consuming` (reversed): syntax error — must be `consuming sending`")
print("- `consuming` is mandatory for ~Copyable value transfer")
