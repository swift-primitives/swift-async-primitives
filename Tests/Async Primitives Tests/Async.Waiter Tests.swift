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

// MARK: - Test Suites

enum Waiter {
    enum Test {
        @Suite struct Flag {}
        @Suite struct Entry {}
        @Suite struct Queue {}
    }
}

// MARK: - Flag Tests

extension Waiter.Test.Flag {
    @Test
    func `init creates unflagged state`() {
        let flag = Async.Waiter.Flag()
        #expect(!flag.cancelled)
        #expect(!flag.timedOut)
        #expect(!flag.isFlagged)
        #expect(flag.reason == nil)
    }

    @Test
    func `cancel sets cancelled flag`() {
        let flag = Async.Waiter.Flag()
        let didSet = flag.cancel()
        #expect(didSet)
        #expect(flag.cancelled)
        #expect(flag.isFlagged)
    }

    @Test
    func `cancel returns false on second call`() {
        let flag = Async.Waiter.Flag()
        #expect(flag.cancel())
        #expect(!flag.cancel())
    }

    @Test
    func `timeout sets timedOut flag`() {
        let flag = Async.Waiter.Flag()
        let didSet = flag.timeout()
        #expect(didSet)
        #expect(flag.timedOut)
        #expect(flag.isFlagged)
    }

    @Test
    func `timeout returns false on second call`() {
        let flag = Async.Waiter.Flag()
        #expect(flag.timeout())
        #expect(!flag.timeout())
    }

    @Test
    func `cancel and timeout are independent`() {
        let flag = Async.Waiter.Flag()
        #expect(flag.cancel())
        #expect(flag.timeout())
        #expect(flag.cancelled)
        #expect(flag.timedOut)
    }

    @Test
    func `reason returns cancelled when only cancelled`() {
        let flag = Async.Waiter.Flag()
        flag.cancel()
        #expect(flag.reason == .cancelled)
    }

    @Test
    func `reason returns timedOut when only timedOut`() {
        let flag = Async.Waiter.Flag()
        flag.timeout()
        #expect(flag.reason == .timedOut)
    }

    @Test
    func `reason prefers cancelled over timedOut`() {
        let flag = Async.Waiter.Flag()
        flag.cancel()
        flag.timeout()
        #expect(flag.reason == .cancelled)
    }

    @Test
    func `reason prefers cancelled regardless of set order`() {
        let flag = Async.Waiter.Flag()
        flag.timeout()
        flag.cancel()
        #expect(flag.reason == .cancelled)
    }

    @Test
    func `reason returns nil when unflagged`() {
        let flag = Async.Waiter.Flag()
        #expect(flag.reason == nil)
    }
}

// MARK: - Entry Tests
//
// Note: Entry<Outcome, Metadata> is ~Copyable. The #expect macro cannot
// capture ~Copyable property accesses, so we extract Copyable values into
// locals before asserting.

extension Waiter.Test.Entry {
    @Test
    func `entry stores flag reference`() {
        let flag = Async.Waiter.Flag()
        let cont = Async.Continuation<Int> { _ in }
        let entry = Async.Waiter.Entry(continuation: cont, flag: flag)
        let isFlagged = entry.flag.isFlagged
        #expect(!isFlagged)
        // Flag is shared by reference — mutation visible through entry
        flag.cancel()
        let nowCancelled = entry.flag.cancelled
        #expect(nowCancelled)
        _ = consume entry
    }

    @Test
    func `entry convenience init without metadata`() {
        let flag = Async.Waiter.Flag()
        let cont = Async.Continuation<Bool> { _ in }
        let entry = Async.Waiter.Entry(continuation: cont, flag: flag)
        let isFlagged = entry.flag.isFlagged
        #expect(!isFlagged)
        _ = consume entry
    }

    @Test
    func `resumption resumes continuation with outcome`() {
        let publication = Async.Publication<Int>()
        let flag = Async.Waiter.Flag()
        let cont = Async.Continuation<Int> { value in
            publication.publish(value)
        }
        let entry = Async.Waiter.Entry(continuation: cont, flag: flag)
        let resumption = entry.resumption(with: 99)
        resumption.resume()
        #expect(publication.take() == 99)
    }

    @Test
    func `resumption with different outcome types`() {
        let publication = Async.Publication<Bool>()
        let flag = Async.Waiter.Flag()
        let cont = Async.Continuation<Bool> { value in
            publication.publish(value)
        }
        let entry = Async.Waiter.Entry(continuation: cont, flag: flag)
        entry.resumption(with: true).resume()
        #expect(publication.take() == true)
    }
}

// MARK: - Queue Tests
//
// Note: Queue<Entry>, Flagged, and Entry are ~Copyable. Property accesses
// on ~Copyable types must be extracted to Copyable locals before passing
// to #expect, which internally captures the expression via closure.

extension Waiter.Test.Queue {
    @Test
    func `popEligible returns unflagged entry`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        let flag = Async.Waiter.Flag()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        if let eligible = queue.popEligible(flaggedInto: &flagged) {
            let isFlagged = eligible.flag.isFlagged
            #expect(!isFlagged)
            _ = consume eligible
        } else {
            Issue.record("Expected an eligible entry")
        }
    }

    @Test
    func `popEligible skips cancelled entries`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        // Cancelled entry
        let flag1 = Async.Waiter.Flag()
        flag1.cancel()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag1
            )
        )

        // Unflagged entry
        let flag2 = Async.Waiter.Flag()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag2
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        if let eligible = queue.popEligible(flaggedInto: &flagged) {
            let isFlagged = eligible.flag.isFlagged
            #expect(!isFlagged)
            _ = consume eligible
        } else {
            Issue.record("Expected an eligible entry")
        }

        // One cancelled entry should be in the drain
        var flaggedCount = 0
        while !flagged.isEmpty {
            _ = flagged.dequeue()
            flaggedCount += 1
        }
        #expect(flaggedCount == 1)
    }

    @Test
    func `popEligible skips timed out entries`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        // Timed out entry
        let flag1 = Async.Waiter.Flag()
        flag1.timeout()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag1
            )
        )

        // Unflagged entry
        let flag2 = Async.Waiter.Flag()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag2
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        if let eligible = queue.popEligible(flaggedInto: &flagged) {
            let isFlagged = eligible.flag.isFlagged
            #expect(!isFlagged)
            _ = consume eligible
        } else {
            Issue.record("Expected an eligible entry")
        }

        var flaggedCount = 0
        while !flagged.isEmpty {
            _ = flagged.dequeue()
            flaggedCount += 1
        }
        #expect(flaggedCount == 1)
    }

    @Test
    func `popEligible skips multiple flagged entries`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        // Two flagged entries
        let flag1 = Async.Waiter.Flag()
        flag1.cancel()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag1
            )
        )

        let flag2 = Async.Waiter.Flag()
        flag2.timeout()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag2
            )
        )

        // One unflagged entry
        let flag3 = Async.Waiter.Flag()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag3
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        if let eligible = queue.popEligible(flaggedInto: &flagged) {
            let isFlagged = eligible.flag.isFlagged
            #expect(!isFlagged)
            _ = consume eligible
        } else {
            Issue.record("Expected an eligible entry")
        }

        var flaggedCount = 0
        while !flagged.isEmpty {
            _ = flagged.dequeue()
            flaggedCount += 1
        }
        #expect(flaggedCount == 2)
    }

    @Test
    func `popEligible returns nil when all flagged`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        let flag1 = Async.Waiter.Flag()
        flag1.cancel()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag1
            )
        )

        let flag2 = Async.Waiter.Flag()
        flag2.timeout()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag2
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        if let eligible = queue.popEligible(flaggedInto: &flagged) {
            Issue.record("Expected nil but got an eligible entry")
            _ = consume eligible
        }

        // Both entries should be in flagged drain
        var flaggedCount = 0
        while !flagged.isEmpty {
            _ = flagged.dequeue()
            flaggedCount += 1
        }
        #expect(flaggedCount == 2)
    }

    @Test
    func `popEligible returns nil from empty queue`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()
        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        if let eligible = queue.popEligible(flaggedInto: &flagged) {
            Issue.record("Expected nil from empty queue")
            _ = consume eligible
        }
    }

    @Test
    func `reapFlagged collects flagged and retains unflagged`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        // Unflagged
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: Async.Waiter.Flag()
            )
        )

        // Cancelled
        let flagCancel = Async.Waiter.Flag()
        flagCancel.cancel()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flagCancel
            )
        )

        // Unflagged
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: Async.Waiter.Flag()
            )
        )

        // Timed out
        let flagTimeout = Async.Waiter.Flag()
        flagTimeout.timeout()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flagTimeout
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        queue.reapFlagged(into: &flagged)

        // 2 flagged entries collected
        var flaggedCount = 0
        while !flagged.isEmpty {
            _ = flagged.dequeue()
            flaggedCount += 1
        }
        #expect(flaggedCount == 2)

        // 2 unflagged entries remain
        var remainingCount = 0
        while !queue.isEmpty {
            _ = queue.dequeue()
            remainingCount += 1
        }
        #expect(remainingCount == 2)
    }

    @Test
    func `reapFlagged on empty queue produces no flagged entries`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()
        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        queue.reapFlagged(into: &flagged)
        let isEmpty = flagged.isEmpty
        #expect(isEmpty)
    }

    @Test
    func `reapFlagged with no flagged entries preserves all`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: Async.Waiter.Flag()
            )
        )
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: Async.Waiter.Flag()
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        queue.reapFlagged(into: &flagged)

        let noFlagged = flagged.isEmpty
        #expect(noFlagged)

        var remainingCount = 0
        while !queue.isEmpty {
            _ = queue.dequeue()
            remainingCount += 1
        }
        #expect(remainingCount == 2)
    }

    @Test
    func `flagged entry preserves cancel reason`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        let flag = Async.Waiter.Flag()
        flag.cancel()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        _ = queue.popEligible(flaggedInto: &flagged)

        if let entry = flagged.dequeue() {
            let reason = entry.reason
            #expect(reason == .cancelled)
            _ = consume entry
        } else {
            Issue.record("Expected a flagged entry")
        }
    }

    @Test
    func `flagged entry preserves timeout reason`() {
        var queue = Async.Waiter.Queue.Unbounded<Bool, Void>()

        let flag = Async.Waiter.Flag()
        flag.timeout()
        queue.enqueue(
            Async.Waiter.Entry(
                continuation: Async.Continuation<Bool> { _ in },
                flag: flag
            )
        )

        var flagged = Async.Waiter.Queue.Drain<Async.Waiter.Queue.Flagged<Bool, Void>>()
        _ = queue.popEligible(flaggedInto: &flagged)

        if let entry = flagged.dequeue() {
            let reason = entry.reason
            #expect(reason == .timedOut)
            _ = consume entry
        } else {
            Issue.record("Expected a flagged entry")
        }
    }

    @Test
    func `flagged split deconstructs into components`() {
        let flag = Async.Waiter.Flag()
        flag.timeout()
        let entry = Async.Waiter.Entry(
            continuation: Async.Continuation<Bool> { _ in },
            flag: flag
        )
        let flaggedEntry = Async.Waiter.Queue.Flagged(reason: .timedOut, entry: entry)
        let split = flaggedEntry.split()
        let reason = split.reason
        let isTimedOut = split.entry.flag.timedOut
        #expect(reason == .timedOut)
        #expect(isTimedOut)
        _ = consume split
    }
}
