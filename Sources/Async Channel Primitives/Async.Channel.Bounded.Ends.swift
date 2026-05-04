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

    extension Async.Channel.Bounded where Element: ~Copyable {
        /// Bundle containing both sender and receiver.
        ///
        /// `Ends` is `~Copyable` because it contains the `~Copyable` receiver.
        /// Use `channel.take().ends()` to consume the channel and obtain this bundle.
        ///
        /// ## Receiver vs Sender Asymmetry
        ///
        /// `receiver` is a stored `~Copyable` property (cursor state lives in
        /// `_receiver`, accessed via `_read` / `_modify` yielding semantics).
        /// `sender` is a computed property synthesizing a fresh `Sender` from
        /// `storage` on each access — `let s1 = ends.sender; let s2 = ends.sender`
        /// produces two distinct Sender values that share the same underlying
        /// storage refcount via `Sender`'s ARC-mediated handle (see
        /// ``Async/Channel/Bounded/Sender`` "Auto-Close (ARC-Mediated)").
        /// The asymmetry is intentional: receivers carry per-receiver cursor
        /// state and so are `~Copyable`; senders are re-derivable views of
        /// the shared storage.
        public struct Ends: ~Copyable, Sendable {
            @usableFromInline
            let storage: Storage

            @usableFromInline
            var _receiver: Receiver

            @usableFromInline
            init(storage: Storage, receiver: consuming Receiver) {
                self.storage = storage
                self._receiver = receiver
            }
        }
    }

    extension Async.Channel.Bounded.Ends where Element: ~Copyable {
        /// View for receiving elements.
        public var receiver: Async.Channel<Element>.Bounded.Receiver {
            _read {
                yield _receiver
            }
            _modify {
                yield &_receiver
            }
        }

        /// View for sending elements.
        public var sender: Async.Channel<Element>.Bounded.Sender {
            Async.Channel<Element>.Bounded.Sender(storage: storage)
        }

        /// Close the channel.
        ///
        /// Equivalent to calling `close()` on a `Sender` view of this channel:
        /// suspended senders throw `Error.closed` (forced), but receivers
        /// continue draining the buffer in FIFO order until empty (graceful).
        /// See ``Async/Channel/Bounded/Sender/close()`` for the full hybrid
        /// forced/graceful semantics.
        public func close() {
            sender.close()
        }

        /// Whether the channel has been closed.
        public var isClosed: Bool {
            sender.isClosed
        }
    }

#endif  // !hasFeature(Embedded)
