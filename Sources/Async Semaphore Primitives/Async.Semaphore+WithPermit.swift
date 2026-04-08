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

#if !hasFeature(Embedded)

// MARK: - Scoped Permit

extension Async.Semaphore {
    /// Acquires a permit, executes the body, and releases the permit.
    ///
    /// The permit is guaranteed to be released even if the body throws.
    /// This is the recommended way to use the semaphore for scoped access.
    ///
    /// Errors from the body are propagated via the generic `E` error type.
    /// Semaphore-level errors (shutdown, cancelled, timeout) throw `Async.Semaphore.Error`.
    ///
    /// - Parameter body: The work to perform while holding the permit.
    /// - Returns: The result of the body.
    /// - Throws: `Async.Semaphore.Error` on acquisition failure, or the body's error type.
    nonisolated(nonsending)
    public func withPermit<T: Sendable>(
        _ body: sending @escaping () async throws(Async.Semaphore.Error) -> sending T
    ) async throws(Async.Semaphore.Error) -> sending T {
        try await wait()
        do throws(Async.Semaphore.Error) {
            let result = try await body()
            signal()
            return result
        } catch {
            signal()
            throw error
        }
    }
}
#endif
