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

    public import Algebra_Primitives_Core

    // MARK: - Scoped Permit

    extension Async.Semaphore {
        /// Acquires a permit, executes the body, and releases the permit.
        ///
        /// The permit is guaranteed to be released even if the body throws.
        /// This is the recommended way to use the semaphore for scoped access.
        ///
        /// ## Error Surface
        ///
        /// - Semaphore acquisition failures (`shutdown`, `cancelled`) are surfaced
        ///   as `Either.left(Async.Semaphore.Error)`.
        /// - Body failures (`E`) are surfaced as `Either.right(E)`.
        /// - For non-throwing bodies, `E` is inferred to `Never` and the `.right`
        ///   case is statically unreachable.
        ///
        /// - Parameter body: The work to perform while holding the permit.
        /// - Returns: The result of the body.
        /// - Throws: `Either<Async.Semaphore.Error, E>` where `.left` is an
        ///   acquisition failure and `.right` is a body failure.
        nonisolated(nonsending)
            public func withPermit<T: Sendable, E: Swift.Error>(
                _ body: sending @escaping () async throws(E) -> sending T
            ) async throws(Either<Async.Semaphore.Error, E>) -> sending T
        {
            do throws(Async.Semaphore.Error) {
                try await wait()
            } catch {
                throw .left(error)
            }
            do throws(E) {
                let result = try await body()
                signal()
                return result
            } catch {
                signal()
                throw .right(error)
            }
        }
    }
#endif
