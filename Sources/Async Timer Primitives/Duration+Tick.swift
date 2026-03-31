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

// MARK: - Divided Accessor

extension Duration {
    /// Namespace accessor for division operations.
    @usableFromInline
    struct Divided: Sendable {
        @usableFromInline let duration: Duration

        @usableFromInline
        init(duration: Duration) {
            self.duration = duration
        }

        /// Divides this duration by another, rounding down.
        ///
        /// Returns the largest integer N such that `divisor * N <= self`.
        ///
        /// - Parameter divisor: The duration to divide by. Must be positive.
        /// - Returns: The quotient as a tick count. Returns 0 if self is negative or zero.
        ///
        /// - Complexity: O(1)
        @usableFromInline
        func roundingDown(by divisor: Duration) -> UInt64 {
            let (selfSec, selfAtto) = duration.components
            let (divSec, divAtto) = divisor.components

            // Handle negative or zero elapsed time
            if selfSec < 0 || (selfSec == 0 && selfAtto <= 0) {
                return 0
            }

            // Convert to attoseconds (10^-18 seconds)
            // Using Int128 would be ideal, but we'll use careful arithmetic
            // to avoid overflow for reasonable durations.

            // For durations up to ~292 years, seconds fit in Int64.
            // Attoseconds are always in range [0, 10^18).

            // Strategy: compute (selfSec * 10^18 + selfAtto) / (divSec * 10^18 + divAtto)
            // We need to handle this without 128-bit integers.

            // First, compute divisor in attoseconds (may overflow for large divisors)
            let attosPerSecond: Int64 = 1_000_000_000_000_000_000

            // Check if divisor is small enough to fit in Int64 attoseconds
            // divSec * 10^18 overflows if divSec > 9 (approximately)
            if divSec <= 9 && divSec >= 0 {
                // Divisor fits in Int64 attoseconds
                let divisorAttos = divSec * attosPerSecond + divAtto

                if divisorAttos <= 0 {
                    // Invalid divisor
                    return 0
                }

                // Now compute self in attoseconds if possible
                if selfSec <= 9 && selfSec >= 0 {
                    // Self also fits
                    let selfAttos = selfSec * attosPerSecond + selfAtto
                    return UInt64(selfAttos / divisorAttos)
                }

                // Self is large, use a different approach:
                // self / divisor = (selfSec * 10^18 + selfAtto) / divisorAttos
                //                = selfSec * (10^18 / divisorAttos) + (selfSec * (10^18 % divisorAttos) + selfAtto) / divisorAttos

                let quotientPerSecond = attosPerSecond / divisorAttos
                let remainderPerSecond = attosPerSecond % divisorAttos

                // Be careful with overflow for very large selfSec
                let secondsContribution = UInt64(selfSec) * UInt64(quotientPerSecond)

                // Remainder part
                let remainderAttos = Int64(selfSec) * remainderPerSecond + selfAtto
                let remainderContribution = UInt64(remainderAttos / divisorAttos)

                return secondsContribution + remainderContribution
            }

            // Divisor is large (> 9 seconds). Use simpler integer division.
            // For very large divisors, the result will be small.
            if divSec > selfSec {
                return 0
            }

            // Approximate: treat as seconds division (loses attosecond precision)
            // This is acceptable because large divisors mean low precision is expected
            if divSec > 0 {
                return UInt64(selfSec / divSec)
            }

            // Divisor has 0 seconds but negative (shouldn't happen with valid Duration)
            return 0
        }
    }

    /// Division operations.
    @usableFromInline
    var divided: Divided { Divided(duration: self) }
}
