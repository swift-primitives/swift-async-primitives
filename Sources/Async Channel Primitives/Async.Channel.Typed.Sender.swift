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
        /// The copyable endpoint that sends elements and terminates the receiver.
        public struct Sender: Sendable {
            @usableFromInline let raw: Async.Channel<Element>.Bounded.Sender
            @usableFromInline let terminals: TerminalStorage

            @usableFromInline
            init(raw: Async.Channel<Element>.Bounded.Sender, terminals: TerminalStorage) {
                self.raw = raw
                self.terminals = terminals
            }
        }
    }

    extension Async.Channel.Typed.Sender where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// Sends an element, suspending under bounded backpressure.
        public func send(_ element: consuming sending Element) async throws(Error) {
            if let terminal = terminals.terminal(from: .receiver) {
                throw Error(terminal: terminal)
            }

            do throws(Async._ChannelError) {
                try await raw.send(consume element)
            } catch {
                throw Error(raw: error, terminal: terminals.terminal(from: .receiver))
            }
        }

        /// Finishes the receiver successfully. The first terminal operation wins.
        public func finish() {
            guard terminals.install(.finished, from: .sender) else { return }
            raw.close()
        }

        /// Fails the receiver after it drains already-buffered elements.
        /// The first terminal operation wins.
        public func fail(_ failure: consuming Failure) {
            guard terminals.install(.failed(consume failure), from: .sender) else { return }
            raw.close()
        }
    }

#endif  // !hasFeature(Embedded)
