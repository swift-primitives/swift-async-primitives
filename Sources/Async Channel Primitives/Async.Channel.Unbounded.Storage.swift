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
    final class Storage: @unchecked Sendable {
        @usableFromInline
        let mutex: Mutex<State>

        /// Slot for transferring ~Copyable elements outside the continuation.
        /// The continuation carries a lightweight Signal; the element travels here.
        @usableFromInline
        let deliverySlot: Ownership.Slot<Element>

        @usableFromInline
        init() {
            self.mutex = Mutex(State())
            self.deliverySlot = Ownership.Slot()
        }

        @inlinable
        func withLock<T: ~Copyable, E: Swift.Error>(_ body: (inout sending State) throws(E) -> sending T) throws(E) -> sending T {
            try mutex.withLock(body)
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
