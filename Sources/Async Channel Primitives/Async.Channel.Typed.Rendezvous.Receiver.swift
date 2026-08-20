// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-async open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-async project authors
// Licensed under Apache License v2.0
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)

    extension Async.Channel.Typed.Rendezvous
    where Element: ~Copyable, Failure: Swift.Error & Sendable {
        /// The single-consumer rendezvous receiving endpoint.
        public struct Receiver: ~Copyable, Sendable {
            @usableFromInline let storage: Storage

            @usableFromInline
            init(storage: Storage) {
                self.storage = storage
            }
        }
    }

    extension Async.Channel.Typed.Rendezvous.Receiver
    where Element: ~Copyable, Failure: Swift.Error & Sendable {
        @usableFromInline
        final class Waiter: Sendable {
            @usableFromInline typealias Continuation = Async.Continuation<Signal>.Unsafe
            @usableFromInline let element: Ownership.Slot<Element>
            @usableFromInline let continuation: Ownership.Slot<Continuation>
            @usableFromInline let flag: Async.Waiter.Flag

            @usableFromInline
            init() {
                self.element = Ownership.Slot()
                self.continuation = Ownership.Slot()
                self.flag = Async.Waiter.Flag()
            }
        }

        @usableFromInline
        enum Signal: Sendable {
            case delivered
            case terminal(Async.Channel<Element>.Typed<Failure>.Terminal)
            case cancelled
        }

        /// Receives from the oldest waiting sender without intermediate storage.
        public func receive() async throws(Error) -> sending Element? {
            let waiter = Waiter()
            let signal: Signal = await withTaskCancellationHandler {
                await unsafe withUnsafeContinuation { (raw: UnsafeContinuation<Signal, Never>) in
                    _ = waiter.continuation.store(unsafe Async.Continuation.Unsafe(raw))
                    var terminal: Async.Channel<Element>.Typed<Failure>.Terminal?
                    var cancelledSelf = false
                    var cancelled = Deque<
                        Column.Ring<Async.Channel<Element>.Typed<Failure>.Rendezvous.Sender.Waiter>
                    >()
                    let sender = storage.withLock {
                        state -> Async.Channel<Element>.Typed<Failure>.Rendezvous.Sender.Waiter? in
                        if waiter.flag.isFlagged {
                            cancelledSelf = true
                            return nil
                        }
                        if let installed = state.senderTerminal ?? state.receiverTerminal {
                            terminal = installed
                            return nil
                        }
                        while let candidate = state.senders.take(from: .front) {
                            if candidate.flag.isFlagged {
                                cancelled.push(candidate, to: .back)
                                continue
                            }
                            return candidate
                        }
                        state.receivers.push(waiter, to: .back)
                        return nil
                    }
                    while let sender = cancelled.take(from: .front) {
                        sender.continuation.take()?.resume(returning: .rejected(.cancelled))
                    }
                    if cancelledSelf {
                        waiter.continuation.take()?.resume(returning: .cancelled)
                    } else if let terminal {
                        waiter.continuation.take()?.resume(returning: .terminal(terminal))
                    }
                    if let sender {
                        let value = sender.element.take(__unchecked: ())
                        _ = waiter.element.store(consume value)
                        sender.continuation.take(__unchecked: ()).resume(returning: .sent)
                        waiter.continuation.take(__unchecked: ()).resume(returning: .delivered)
                    }
                }
            } onCancel: {
                guard waiter.flag.cancel() else { return }
                let removed = storage.withLock { state -> Waiter? in
                    var survivors = Deque<Column.Ring<Waiter>>()
                    var removed: Waiter?
                    while let candidate = state.receivers.take(from: .front) {
                        if candidate === waiter {
                            removed = candidate
                        } else {
                            survivors.push(candidate, to: .back)
                        }
                    }
                    state.receivers = consume survivors
                    return removed
                }
                removed?.continuation.take()?.resume(returning: .cancelled)
            }

            switch signal {
            case .delivered:
                return waiter.element.take(__unchecked: ())

            case .terminal(.finished):
                return nil

            case .terminal(.failed(let failure)):
                throw .failed(failure)

            case .cancelled:
                throw .cancelled
            }
        }

        /// Finishes all senders successfully. The first receiver terminal wins.
        public func finish() {
            terminate(.finished)
        }

        /// Fails all senders with the declared failure. The first receiver terminal wins.
        public func fail(_ failure: consuming Failure) {
            terminate(.failed(consume failure))
        }

        @usableFromInline
        func terminate(_ terminal: Async.Channel<Element>.Typed<Failure>.Terminal) {
            var senders = Deque<
                Column.Ring<Async.Channel<Element>.Typed<Failure>.Rendezvous.Sender.Waiter>
            >()
            storage.withLock { state in
                guard state.receiverTerminal == nil else { return }
                state.receiverTerminal = terminal
                senders = consume state.senders
                state.senders = Deque()
            }
            while let sender = senders.take(from: .front) {
                sender.continuation.take()?.resume(returning: .rejected(Error(terminal: terminal)))
            }
        }
    }

#endif  // !hasFeature(Embedded)
