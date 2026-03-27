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

public import Synchronization

extension Async.Channel.Unbounded {
    /// Thread-safe storage wrapping the state machine.
    @usableFromInline
    final class Storage: @unchecked Sendable {
        @usableFromInline
        let mutex: Mutex<State>

        @usableFromInline
        init() {
            self.mutex = Mutex(State())
        }

        @inlinable
        func withLock<T, E: Swift.Error>(_ body: (inout State) throws(E) -> T) throws(E) -> T {
            try mutex.withLock { (state: inout State) throws(E) -> T in
                try body(&state)
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
