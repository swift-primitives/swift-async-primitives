// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    /// The typed outcome of a channel endpoint operation.
    public enum _TypedChannelError<Failure: Swift.Error & Sendable>: Swift.Error, Sendable {
        /// The endpoint was closed without a directional terminal operation.
        case closed

        /// The waiting task was cancelled.
        case cancelled

        /// An immediate send would have suspended for capacity.
        case full

        /// An immediate receive would have suspended for an element.
        case empty

        /// The opposite endpoint finished successfully.
        case finished

        /// The opposite endpoint failed with its declared failure.
        case failed(Failure)
    }

    extension _TypedChannelError {
        @usableFromInline
        init<Element>(terminal: Async.Channel<Element>.Typed<Failure>.Terminal)
        where Element: ~Copyable {
            switch terminal {
            case .finished: self = .finished
            case .failed(let failure): self = .failed(failure)
            }
        }

        @usableFromInline
        init<Element>(
            raw: Async._ChannelError,
            terminal: Async.Channel<Element>.Typed<Failure>.Terminal?
        ) where Element: ~Copyable {
            switch terminal {
            case let terminal?: self.init(terminal: terminal)

            case nil:
                switch raw {
                case .closed: self = .closed
                case .cancelled: self = .cancelled
                case .full: self = .full
                case .empty: self = .empty
                }
            }
        }
    }

#endif  // !hasFeature(Embedded)
