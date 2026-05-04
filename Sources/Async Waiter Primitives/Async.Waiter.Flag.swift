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

public import Synchronization

extension Async.Waiter {
    /// Atomic flags for cancellation and timeout signaling.
    ///
    /// ## Thread Safety
    ///
    /// Flag uses atomic operations to allow safe concurrent access:
    /// - **Writers** (cancel/timeout handlers): Set flags from any thread
    /// - **Readers** (queue pump): Check flags under lock
    ///
    /// This pattern is safe because:
    /// 1. Flags are monotonic (`false` → `true`, never reset)
    /// 2. Atomic loads/stores prevent torn reads
    /// 3. Relaxed ordering suffices (no cross-flag dependencies)
    ///
    /// ## Usage Pattern
    ///
    /// ```swift
    /// let flag = Async.Waiter.Flag()
    ///
    /// // In cancellation handler (outside lock):
    /// if flag.cancel() {
    ///     pumpWaiters()  // Only pump if we were the one to set it
    /// }
    ///
    /// // In timeout handler (outside lock):
    /// if flag.timeout() {
    ///     pumpWaiters()
    /// }
    ///
    /// // Under lock during pump:
    /// if flag.cancelled { ... }
    /// if flag.timedOut { ... }
    /// ```
    ///
    /// ## Precedence
    ///
    /// When both flags are set, the caller determines precedence.
    /// Standard precedence is: cancellation > timeout.
    public final class Flag: Sendable {
        @usableFromInline
        let _bits: Atomic<UInt8>

        /// Creates a new flag with both bits clear.
        public init() {
            self._bits = Atomic(0)
        }
    }
}

// MARK: - Flag Operations

extension Async.Waiter.Flag {
    @usableFromInline
    static let cancelledBit: UInt8 = 1

    @usableFromInline
    static let timedOutBit: UInt8 = 2

    /// Whether the waiter has been cancelled (read-only).
    public var cancelled: Bool {
        _bits.load(ordering: .relaxed) & Self.cancelledBit != 0
    }

    /// Whether the waiter has timed out (read-only).
    public var timedOut: Bool {
        _bits.load(ordering: .relaxed) & Self.timedOutBit != 0
    }

    /// Whether either flag is set (read-only).
    public var isFlagged: Bool {
        _bits.load(ordering: .relaxed) != 0
    }

    /// Atomically sets the cancelled flag.
    ///
    /// This operation is atomic (CAS loop) and monotonic: once set, the flag
    /// cannot be cleared. Returns `true` only for the first successful transition;
    /// subsequent calls return `false`. Multiple concurrent calls are safe.
    ///
    /// Ordering is relaxed because queue state is synchronized separately
    /// via the caller's mutex.
    ///
    /// - Returns: `true` if this call transitioned the flag from unset to set.
    @discardableResult
    public func cancel() -> Bool {
        setFlag(Self.cancelledBit)
    }

    /// Atomically sets the timed out flag.
    ///
    /// This operation is atomic (CAS loop) and monotonic: once set, the flag
    /// cannot be cleared. Returns `true` only for the first successful transition;
    /// subsequent calls return `false`. Multiple concurrent calls are safe.
    ///
    /// Ordering is relaxed because queue state is synchronized separately
    /// via the caller's mutex.
    ///
    /// - Returns: `true` if this call transitioned the flag from unset to set.
    @discardableResult
    public func timeout() -> Bool {
        setFlag(Self.timedOutBit)
    }

    /// Atomically sets a flag bit using compare-and-swap loop.
    ///
    /// - Parameter mask: The bit mask to set.
    /// - Returns: `true` if this call set the bit (was previously unset).
    private func setFlag(_ mask: UInt8) -> Bool {
        var current = _bits.load(ordering: .relaxed)
        while true {
            let next = current | mask
            if next == current {
                // Already set
                return false
            }
            let result = _bits.compareExchange(
                expected: current,
                desired: next,
                ordering: .relaxed
            )
            if result.exchanged {
                return true
            }
            // CAS failed - reuse observed value for next iteration
            current = result.original
        }
    }
}
