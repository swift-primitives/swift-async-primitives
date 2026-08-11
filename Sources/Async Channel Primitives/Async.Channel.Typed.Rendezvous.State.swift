// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    extension Async.Channel.Typed.Rendezvous where Element: ~Copyable, Failure: Swift.Error & Sendable {
        @usableFromInline
        struct State: ~Copyable {
            @usableFromInline var senderTerminal: Async.Channel<Element>.Typed<Failure>.Terminal?
            @usableFromInline var receiverTerminal: Async.Channel<Element>.Typed<Failure>.Terminal?
            @usableFromInline var senders: Deque<Column.Ring<Sender.Waiter>>
            @usableFromInline var receivers: Deque<Column.Ring<Receiver.Waiter>>

            @usableFromInline
            init() {
                senderTerminal = nil
                receiverTerminal = nil
                senders = Deque()
                receivers = Deque()
            }
        }
    }

#endif  // !hasFeature(Embedded)
