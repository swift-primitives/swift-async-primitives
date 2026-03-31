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

// Async channels require task suspension which is not available on embedded Swift.
#if !hasFeature(Embedded)

extension Async.Channel.Bounded.Receiver where Element: ~Copyable {
    /// Receive operation accessor with variants.
    public struct Receive: Sendable {
        @usableFromInline
        let storage: Async.Channel<Element>.Bounded.Storage

        @usableFromInline
        init(storage: Async.Channel<Element>.Bounded.Storage) {
            self.storage = storage
        }

        /// Receive an element without suspending.
        ///
        /// - Returns: The next element if available, `nil` if the channel is closed and drained.
        /// - Throws: `.empty` if the buffer is empty, `.cancelled` if the task was cancelled.
        // WORKAROUND: @_optimize(none) — see Storage.handleReceive workaround comment.
        @_optimize(none)
        @inlinable
        public func immediate() throws(Async.Channel<Element>.Error) -> Element? {
            let action = storage.withLock { state in
                state.receive()
            }

            switch consume action {
            case .returnElement(let element, let resumeSender, var cancelled):
                // Resume cancelled senders first (minimizes stuck time)
                while let c = cancelled?.take(from: .front) {
                    c.resume(returning: .cancelled)
                }
                resumeSender?.resume(returning: nil)
                return element
            case .returnNil:
                return nil
            case .rejectCancelled:
                throw .cancelled
            case .suspend:
                throw .empty
            }
        }
    }
}

#endif  // !hasFeature(Embedded)
