// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    extension Async.Channel.Typed where Element: ~Copyable, Failure: Swift.Error & Sendable {
        @usableFromInline
        enum Terminal: Sendable {
            case finished
            case failed(Failure)
        }

        @usableFromInline
        enum Direction: Sendable {
            case sender
            case receiver
        }

        @usableFromInline
        struct Terminals: Sendable {
            @usableFromInline var sender: Terminal?
            @usableFromInline var receiver: Terminal?
        }

        @usableFromInline
        final class TerminalStorage: Sendable {
            @usableFromInline let mutex: Async.Mutex<Terminals>

            @usableFromInline
            init() {
                mutex = Async.Mutex(Terminals(sender: nil, receiver: nil))
            }

            @usableFromInline
            func install(_ terminal: Terminal, from direction: Direction) -> Bool {
                mutex.withLock { terminals in
                    switch direction {
                    case .sender:
                        guard terminals.sender == nil else { return false }
                        terminals.sender = terminal
                        return true

                    case .receiver:
                        guard terminals.receiver == nil else { return false }
                        terminals.receiver = terminal
                        return true
                    }
                }
            }

            @usableFromInline
            func terminal(from direction: Direction) -> Terminal? {
                mutex.withLock { terminals in
                    switch direction {
                    case .sender: terminals.sender
                    case .receiver: terminals.receiver
                    }
                }
            }
        }
    }

#endif  // !hasFeature(Embedded)
