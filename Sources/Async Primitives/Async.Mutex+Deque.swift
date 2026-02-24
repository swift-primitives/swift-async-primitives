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

#if !hasFeature(Embedded)
public import Synchronization
#endif
public import Queue_Primitives
public import Buffer_Primitives

// MARK: - Async.Mutex<Deque<Element>> Queue Operations

/// Queue operations on `Async.Mutex<Deque<Element>>`.
///
/// Provides thread-safe FIFO queue semantics over a deque.
///
/// ```swift
/// let queue = Async.Mutex<Deque<Int>>(.init())
///
/// // Producers (any thread)
/// queue.enqueue(1)
/// queue.enqueue(2)
///
/// // Consumer (single thread)
/// while let item = queue.dequeue() {
///     process(item)
/// }
///
/// // Drain all at once
/// let items = queue.drain()
/// ```
extension Async.Mutex {
    /// Adds an element to the back of the queue.
    ///
    /// - Parameter element: The element to add.
    /// - Complexity: O(1) amortized.
    @inlinable
    public func enqueue<Element: Sendable>(_ element: Element) where Value == Deque<Element> {
        withLock { $0.back.push(element) }
    }

    /// Removes and returns the front element, or `nil` if empty.
    ///
    /// - Returns: The front element, or `nil` if the queue is empty.
    /// - Complexity: O(1) amortized.
    @inlinable
    public func dequeue<Element: Sendable>() -> Element? where Value == Deque<Element> {
        withLock { $0.front.take }
    }

    /// Removes and returns all elements.
    ///
    /// - Returns: All elements in FIFO order, or empty array if queue is empty.
    /// - Complexity: O(n) where n is the number of elements.
    @inlinable
    public func drain<Element: Sendable>() -> [Element] where Value == Deque<Element> {
        withLock { deque in
            var result: [Element] = []
            result.reserveCapacity(deque.count)
            while let element = deque.front.take {
                result.append(element)
            }
            return result
        }
    }

    /// Drains all elements into an existing buffer.
    ///
    /// More efficient than `drain()` when reusing a pre-allocated buffer.
    ///
    /// - Parameter target: Buffer to append elements to.
    /// - Complexity: O(n) where n is the number of elements.
    @inlinable
    public func drain<Element: Sendable>(into target: inout [Element]) where Value == Deque<Element> {
        withLock { deque in
            while let element = deque.front.take {
                target.append(element)
            }
        }
    }
}

// MARK: - Shared<Async.Mutex<Deque<Element>>> Queue Operations

// NOTE: Shared type extension commented out pending implementation of Shared type.
// Once Ownership.Shared is implemented, uncomment this section.

//extension Shared where Value: ~Copyable {
//    /// Adds an element to the back of the queue.
//    @inlinable
//    public func enqueue<Element: Sendable>(_ element: Element) where Value == Async.Mutex<Deque<Element>> {
//        self.withValue { $0.enqueue(element) }
//    }
//
//    /// Removes and returns the front element, or `nil` if empty.
//    @inlinable
//    public func dequeue<Element: Sendable>() -> Element? where Value == Async.Mutex<Deque<Element>> {
//        self.withValue { $0.dequeue() }
//    }
//
//    /// Removes and returns all elements.
//    @inlinable
//    public func drain<Element: Sendable>() -> [Element] where Value == Async.Mutex<Deque<Element>> {
//        self.withValue { $0.drain() }
//    }
//
//    /// Drains all elements into an existing buffer.
//    @inlinable
//    public func drain<Element: Sendable>(into target: inout [Element]) where Value == Async.Mutex<Deque<Element>> {
//        self.withValue { $0.drain(into: &target) }
//    }
//}
