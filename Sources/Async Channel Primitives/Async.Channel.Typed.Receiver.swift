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
        /// The single-consumer endpoint that receives elements and terminates senders.
        public struct Receiver: ~Copyable, Sendable {
            @usableFromInline let raw: Async.Channel<Element>.Bounded.Receiver
            @usableFromInline let closer: Async.Channel<Element>.Bounded.Sender
            @usableFromInline let terminals: TerminalStorage

            @usableFromInline
            init(
                raw: consuming Async.Channel<Element>.Bounded.Receiver,
                closer: Async.Channel<Element>.Bounded.Sender,
                terminals: TerminalStorage
            ) {
                self.raw = raw
                self.closer = closer
                self.terminals = terminals
            }
        }
    }

    extension Async.Channel.Typed.Receiver
    where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// Receives an element. Sender failure is reported only after buffered
        /// elements have drained; sender finish is reported as `nil`.
        public func receive() async throws(Error) -> sending Element? {
            do throws(Async._ChannelError) {
                if let element = try await raw.receive() {
                    return element
                }
            } catch {
                throw Error(raw: error, terminal: terminals.terminal(from: .sender))
            }

            if case .failed(let failure)? = terminals.terminal(from: .sender) {
                throw .failed(failure)
            }
            return nil
        }

        /// Finishes all senders successfully. The first terminal operation wins.
        public func finish() {
            guard terminals.install(.finished, from: .receiver) else { return }
            closer.close()
        }

        /// Fails all senders with the declared failure. The first terminal
        /// operation wins.
        public func fail(_ failure: consuming Failure) {
            guard terminals.install(.failed(consume failure), from: .receiver) else { return }
            closer.close()
        }
    }

#endif  // !hasFeature(Embedded)
