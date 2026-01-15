//
//  Mutex+Deque.swift
//  swift-buffer
//
//  Created by Coen ten Thije Boonkkamp on 07/01/2026.
//

public import Synchronization
public import Container_Primitives

// MARK: - Mutex<Deque<Element>> Queue Operations

/// Queue operations on `Mutex<Deque<Element>>`.
///
/// Provides thread-safe FIFO queue semantics over a deque.
///
/// ```swift
/// let queue = Mutex<Deque<Int>>(.init())
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
extension Mutex {
    /// Adds an element to the back of the queue.
    ///
    /// - Parameter element: The element to add.
    /// - Complexity: O(1) amortized.
    @inlinable
    public func enqueue<Element: Sendable>(_ element: Element) where Value == Deque<Element> {
        withLock { $0.push.back(element) }
    }

    /// Removes and returns the front element, or `nil` if empty.
    ///
    /// - Returns: The front element, or `nil` if the queue is empty.
    /// - Complexity: O(1) amortized.
    @inlinable
    public func dequeue<Element: Sendable>() -> Element? where Value == Deque<Element> {
        withLock { $0.take.front }
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
            while let element = deque.take.front {
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
            while let element = deque.take.front {
                target.append(element)
            }
        }
    }
}

// MARK: - Shared<Mutex<Deque<Element>>> Queue Operations

/// Queue operations on `Shared<Mutex<Deque<Element>>>`.
///
/// Provides thread-safe FIFO queue semantics with shared ownership.
///
/// ```swift
/// let queue: Shared<Mutex<Deque<Int>>> = .init(.init(.init()))
///
/// // Producers (any thread, any owner)
/// queue.enqueue(1)
/// queue.enqueue(2)
///
/// // Consumer (any thread)
/// while let item = queue.dequeue() {
///     process(item)
/// }
/// ```
extension Shared where Value: ~Copyable {
    /// Adds an element to the back of the queue.
    @inlinable
    public func enqueue<Element: Sendable>(_ element: Element) where Value == Mutex<Deque<Element>> {
        _value.enqueue(element)
    }

    /// Removes and returns the front element, or `nil` if empty.
    @inlinable
    public func dequeue<Element: Sendable>() -> Element? where Value == Mutex<Deque<Element>> {
        _value.dequeue()
    }

    /// Removes and returns all elements.
    @inlinable
    public func drain<Element: Sendable>() -> [Element] where Value == Mutex<Deque<Element>> {
        _value.drain()
    }

    /// Drains all elements into an existing buffer.
    @inlinable
    public func drain<Element: Sendable>(into target: inout [Element]) where Value == Mutex<Deque<Element>> {
        _value.drain(into: &target)
    }
}
