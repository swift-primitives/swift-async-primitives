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

public import Ownership_Primitives
public import Synchronization

extension Async.Channel.Bounded where Element: ~Copyable {
    /// Thread-safe storage wrapping the state machine.
    ///
    /// Uses `Ownership.Mutable.Unchecked` to give the channel reference semantics
    /// while keeping a struct interface. Thread safety is provided by the
    /// wrapped `Mutex`.
    @usableFromInline
    struct Storage: Sendable {
        @usableFromInline
        let _storage: Ownership.Mutable<Async.Mutex<State>>.Unchecked

        /// Slot for transferring ~Copyable elements outside the continuation.
        /// The continuation carries a lightweight Signal; the element travels here.
        @usableFromInline
        let deliverySlot: Ownership.Slot<Element>

        @usableFromInline
        init(capacity: Index<Element>.Count) {
            self._storage = Ownership.Mutable.Unchecked(Async.Mutex(State(capacity: capacity)))
            self.deliverySlot = Ownership.Slot()
        }
    }
}

extension Async.Channel.Bounded.Storage where Element: ~Copyable {
    @usableFromInline
    typealias State = Async.Channel<Element>.Bounded.State

    @inlinable
    func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout sending State) throws(E) -> sending T) throws(E) -> sending T {
        try _storage.mutable.value.withLock(body)
    }

    // WORKAROUND: @_optimize(none) prevents CopyPropagation ownership
    // verification crash on ~Copyable enum consume in nested async closures.
    // WHY: CopyPropagation fails initializeConsumingUse when optimizing
    //       `switch consume` on ~Copyable enum inside withUnsafeContinuation
    //       closure inside withTaskCancellationHandler.
    // TRACKING: Not yet filed upstream.
    // WHEN TO REMOVE: When the CopyPropagation crash is fixed upstream.
    @_optimize(none)
    @usableFromInline
    static func handleReceive(
        _ action: consuming State.Receive.Action,
        storage: Async.Channel<Element>.Bounded.Storage,
        continuation: State.Receive.Continuation
    ) {
        switch consume action {
        case .returnElement(let element, let resumeSender, let cancelled):
            if var cancelled {
                while let c = cancelled.take(from: .front) {
                    c.resume(returning: .cancelled)
                }
            }
            resumeSender?.resume(returning: nil)
            _ = storage.deliverySlot.store(element)
            continuation.resume(returning: .delivered)
        case .returnNil:
            continuation.resume(returning: .closed)
        case .rejectCancelled:
            continuation.resume(returning: .cancelled)
        case .suspend:
            break
        }
    }

    // WORKAROUND: Same CopyPropagation crash — see handleReceive comment.
    @_optimize(none)
    @usableFromInline
    static func handleSend(
        _ action: consuming State.Send.Action,
        storage: Async.Channel<Element>.Bounded.Storage,
        continuation: State.Send.Continuation
    ) {
        switch consume action {
        case .deliverToReceiver(let receiverCont, let element):
            _ = storage.deliverySlot.store(element)
            receiverCont.resume(returning: State.Receive.Signal.delivered)
            continuation.resume(returning: nil)
        case .buffered:
            continuation.resume(returning: nil)
        case .rejectClosed:
            continuation.resume(returning: .closed)
        case .rejectCancelled:
            continuation.resume(returning: .cancelled)
        case .suspended:
            break
        }
    }
}

#endif  // !hasFeature(Embedded)
