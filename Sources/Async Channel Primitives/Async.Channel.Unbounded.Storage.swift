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

extension Async.Channel.Unbounded where Element: ~Copyable {
    /// Thread-safe storage wrapping the state machine.
    @usableFromInline
    final class Storage: Sendable {
        @usableFromInline
        let mutex: Async.Mutex<State>

        /// Slot for transferring ~Copyable elements outside the continuation.
        /// The continuation carries a lightweight Signal; the element travels here.
        @usableFromInline
        let deliverySlot: Ownership.Slot<Element>

        @usableFromInline
        init() {
            self.mutex = Async.Mutex(State())
            self.deliverySlot = Ownership.Slot()
        }

        @inlinable
        func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout sending State) throws(E) -> sending T) throws(E) -> sending T {
            try mutex.withLock(body)
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
            _ action: consuming State.Receive.Step,
            storage: Storage,
            continuation: State.Receive.Continuation
        ) {
            switch consume action {
            case .val(let element):
                _ = storage.deliverySlot.store(element)
                continuation.resume(returning: .delivered)
            case .end:
                continuation.resume(returning: .closed)
            case .wait:
                break
            case .cancelled:
                continuation.resume(returning: .cancelled)
            }
        }

        deinit {
            let action = withLock { state in
                state.close()
            }

            switch action {
            case .none:
                break
            case .end(let cont):
                cont.resume(returning: .closed)
            }
        }
    }
}

#endif  // !hasFeature(Embedded)
