// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025-2026 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Async_Primitives_Test_Support
import Testing

@Suite
struct BridgeTests {

    @Test
    func `next() does not observe Task cancellation`() async {
        // Pins the documented contract: Bridge.next() is non-observing
        // by signature (async -> Element?, not throws). A cancelled Task
        // suspended in next() still resumes when push() supplies an
        // element.
        let bridge = Async.Bridge<Int>()

        let task = Task { await bridge.next() }

        // Let the task suspend on next() (buffer is empty)
        try? await Task.sleep(for: .milliseconds(20))

        // Cancel the consumer — should NOT interrupt next()
        task.cancel()

        // Give cancellation time to propagate (it shouldn't, but we test that)
        try? await Task.sleep(for: .milliseconds(20))

        // Push — the cancelled consumer resumes with the element
        bridge.push(42)

        let result = await task.value
        #expect(result == 42, "cancelled consumer still receives the pushed element")
        #expect(task.isCancelled, "task should still report itself as cancelled")
    }

    @Test
    func `next() returns nil after finish on cancelled task`() async {
        // Variant: cancellation mid-await + finish() (no element pushed)
        // → nil return. Confirms finish() signals the cancelled awaiter
        // through the same non-observing path.
        let bridge = Async.Bridge<Int>()

        let task = Task { await bridge.next() }

        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        try? await Task.sleep(for: .milliseconds(20))

        bridge.finish()

        let result = await task.value
        #expect(result == nil, "cancelled consumer resumes with nil after finish()")
    }
}
