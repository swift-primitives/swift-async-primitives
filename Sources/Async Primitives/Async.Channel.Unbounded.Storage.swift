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
        func withLock<T: Sendable>(_ body: (inout State) throws -> T) rethrows -> T {
            try mutex.withLock { state in
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
                cont.resume(returning: (nil, nil))
            }
        }
    }
}
