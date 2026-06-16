// swift-tools-version: 6.3.1

import PackageDescription

let package = Package(
    name: "swift-async-primitives",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        // MARK: - Namespace + foundational ([MOD-017] singular root + [MOD-031] sub-namespaces)
        .library(
            name: "Async Primitive",
            targets: ["Async Primitive"]
        ),
        .library(
            name: "Async Callback Primitives",
            targets: ["Async Callback Primitives"]
        ),
        .library(
            name: "Async Continuation Primitives",
            targets: ["Async Continuation Primitives"]
        ),
        .library(
            name: "Async Lifecycle Primitives",
            targets: ["Async Lifecycle Primitives"]
        ),
        .library(
            name: "Async Precedence Primitives",
            targets: ["Async Precedence Primitives"]
        ),
        // MARK: - Mutex
        .library(
            name: "Async Mutex Primitives",
            targets: ["Async Mutex Primitives"]
        ),
        // MARK: - Coordination
        .library(
            name: "Async Bridge Primitives",
            targets: ["Async Bridge Primitives"]
        ),
        .library(
            name: "Async Promise Primitives",
            targets: ["Async Promise Primitives"]
        ),
        .library(
            name: "Async Publication Primitives",
            targets: ["Async Publication Primitives"]
        ),
        .library(
            name: "Async Barrier Primitives",
            targets: ["Async Barrier Primitives"]
        ),
        .library(
            name: "Async Completion Primitives",
            targets: ["Async Completion Primitives"]
        ),
        // MARK: - Variants
        .library(
            name: "Async Channel Primitives",
            targets: ["Async Channel Primitives"]
        ),
        .library(
            name: "Async Broadcast Primitives",
            targets: ["Async Broadcast Primitives"]
        ),
        // ⚠️ W5-3 QUARANTINE (2026-06-11): the Timer target/product is PARKED out of
        // the build graph — Timer.Wheel rides swift-buffer-arena-primitives (W5-5
        // disposition) + the linked round (ruling D). Restore with its round; sources
        // untouched. (Broadcast restored 2026-06-11 with the W5 ordered round —
        // Dictionary<S>.Ordered over the Hash.Indexed entry column.)
        // .library(
        //     name: "Async Timer Primitives",
        //     targets: ["Async Timer Primitives"]
        // ),
        .library(
            name: "Async Waiter Primitives",
            targets: ["Async Waiter Primitives"]
        ),
        .library(
            name: "Async Semaphore Primitives",
            targets: ["Async Semaphore Primitives"]
        ),
        // MARK: - Umbrella
        .library(
            name: "Async Primitives",
            targets: ["Async Primitives"]
        ),
        .library(
            name: "Async Primitives Test Support",
            targets: ["Async Primitives Test Support"]
        ),
    ],
    dependencies: [
        // .package(url: "https://github.com/swift-primitives/swift-storage-primitives.git", branch: "main"),  // W5-3 quarantine (Timer — Storage Primitive)
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-ring-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-linear-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-storage-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-allocation-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-memory-heap-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dictionary-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dictionary-ordered-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-hash-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-hash-table-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-index-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-queue-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-column-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-deque-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ownership-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
        // .package(url: "https://github.com/swift-primitives/swift-link-primitives.git", branch: "main"),  // W5-3 quarantine (Timer)
        // .package(url: "https://github.com/swift-primitives/swift-buffer-arena-primitives.git", branch: "main"),  // W5-3 quarantine (Timer)
    ],
    targets: [
        // MARK: - Namespace + foundational
        //
        // [MOD-017]: `Async Primitive` (SINGULAR) owns the root `enum Async {}` plus
        // the package's foundational, stdlib-only declarations. Zero external-package
        // dependencies — the load-bearing invariant. [MOD-031]: each sub-namespace
        // `Async.{X}` is its own target.

        .target(
            name: "Async Primitive",
            dependencies: []
        ),
        .target(
            name: "Async Callback Primitives",
            dependencies: ["Async Primitive"]
        ),
        .target(
            name: "Async Continuation Primitives",
            dependencies: ["Async Primitive"]
        ),
        .target(
            name: "Async Lifecycle Primitives",
            dependencies: ["Async Primitive"]
        ),
        .target(
            name: "Async Precedence Primitives",
            dependencies: ["Async Primitive"]
        ),

        // MARK: - Mutex
        .target(
            name: "Async Mutex Primitives",
            dependencies: [
                "Async Primitive"
            ]
        ),

        // MARK: - Coordination
        .target(
            name: "Async Bridge Primitives",
            dependencies: [
                "Async Primitive",
                "Async Mutex Primitives",
                .product(name: "Buffer Primitive", package: "swift-buffer-primitives"),
                .product(name: "Buffer Ring Primitive", package: "swift-buffer-ring-primitives"),
                .product(name: "Column Primitives", package: "swift-column-primitives"),
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
                .product(name: "Memory Allocator Primitive", package: "swift-memory-allocation-primitives"),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Storage Contiguous Primitives", package: "swift-storage-primitives"),
            ]
        ),
        .target(
            name: "Async Promise Primitives",
            dependencies: [
                "Async Primitive",
                "Async Continuation Primitives",
                "Async Mutex Primitives",
            ]
        ),
        .target(
            name: "Async Publication Primitives",
            dependencies: [
                "Async Primitive",
                "Async Mutex Primitives",
            ]
        ),
        .target(
            name: "Async Barrier Primitives",
            dependencies: [
                "Async Primitive",
                "Async Lifecycle Primitives",
                "Async Mutex Primitives",
                "Async Waiter Primitives",
            ]
        ),
        .target(
            name: "Async Completion Primitives",
            dependencies: [
                "Async Primitive",
                "Async Mutex Primitives",
            ]
        ),

        // MARK: - Variants
        .target(
            name: "Async Channel Primitives",
            dependencies: [
                "Async Primitive",
                "Async Continuation Primitives",
                "Async Mutex Primitives",
                "Async Waiter Primitives",
                .product(name: "Buffer Primitive", package: "swift-buffer-primitives"),
                .product(name: "Buffer Ring Primitive", package: "swift-buffer-ring-primitives"),
                .product(name: "Column Primitives", package: "swift-column-primitives"),
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
                .product(name: "Memory Allocator Primitive", package: "swift-memory-allocation-primitives"),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "Storage Contiguous Primitives", package: "swift-storage-primitives"),
            ]
        ),
        .target(
            name: "Async Broadcast Primitives",
            dependencies: [
                "Async Primitive",
                "Async Mutex Primitives",
                "Async Publication Primitives",
                .product(name: "Buffer Linear Primitive", package: "swift-buffer-linear-primitives"),
                .product(name: "Buffer Primitive", package: "swift-buffer-primitives"),
                .product(name: "Buffer Ring Primitive", package: "swift-buffer-ring-primitives"),
                .product(name: "Column Primitives", package: "swift-column-primitives"),
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
                .product(name: "Dictionary Ordered Primitives", package: "swift-dictionary-ordered-primitives"),
                .product(name: "Dictionary Primitives", package: "swift-dictionary-primitives"),
                .product(name: "Hash Indexed Primitive", package: "swift-hash-table-primitives"),
                .product(name: "Hash Primitives", package: "swift-hash-primitives"),
                .product(name: "Index Primitives", package: "swift-index-primitives"),
                .product(name: "Memory Allocator Primitive", package: "swift-memory-allocation-primitives"),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Storage Contiguous Primitives", package: "swift-storage-primitives"),
            ]
        ),
        // ⚠️ W5-3 QUARANTINE (2026-06-11): Timer target PARKED — see products note above.
        //     .target(
        //         name: "Async Timer Primitives",
        //         dependencies: [
        //             .product(name: "Storage Primitive", package: "swift-storage-primitives"),
        //             "Async Primitive",
        //             .product(name: "Link Primitives", package: "swift-link-primitives"),
        //             .product(name: "Buffer Arena Primitive", package: "swift-buffer-arena-primitives"),
        //             .product(name: "Buffer Arena Bounded Primitive", package: "swift-buffer-arena-primitives"),
        //         ]
        //     ),
        .target(
            name: "Async Waiter Primitives",
            dependencies: [
                "Async Primitive",
                "Async Continuation Primitives",
                .product(name: "Buffer Primitive", package: "swift-buffer-primitives"),
                .product(name: "Buffer Ring Bounded Primitive", package: "swift-buffer-ring-primitives"),
                .product(name: "Buffer Ring Primitive", package: "swift-buffer-ring-primitives"),
                .product(name: "Column Primitives", package: "swift-column-primitives"),
                .product(name: "Memory Allocator Primitive", package: "swift-memory-allocation-primitives"),
                .product(name: "Memory Heap Primitives", package: "swift-memory-heap-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Storage Contiguous Primitives", package: "swift-storage-primitives"),
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
            ]
        ),

        // MARK: - Semaphore
        .target(
            name: "Async Semaphore Primitives",
            dependencies: [
                "Async Primitive",
                "Async Continuation Primitives",
                "Async Lifecycle Primitives",
                "Async Precedence Primitives",
                "Async Mutex Primitives",
                "Async Promise Primitives",
                "Async Waiter Primitives",
                .product(name: "Either Primitives", package: "swift-either-primitives"),
                .product(name: "Queue Primitive", package: "swift-queue-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
            ]
        ),

        // MARK: - Umbrella
        //
        // [MOD-005]: re-exports ALL sub-targets (root + sub-namespaces + variants).
        .target(
            name: "Async Primitives",
            dependencies: [
                "Async Primitive",
                "Async Callback Primitives",
                "Async Continuation Primitives",
                "Async Lifecycle Primitives",
                "Async Precedence Primitives",
                "Async Mutex Primitives",
                "Async Bridge Primitives",
                "Async Promise Primitives",
                "Async Publication Primitives",
                "Async Barrier Primitives",
                "Async Completion Primitives",
                "Async Channel Primitives",
                "Async Broadcast Primitives",
                // "Async Timer Primitives",  // W5-3 quarantine
                "Async Waiter Primitives",
                "Async Semaphore Primitives",
            ]
        ),

        // Tests in nested Tests/Package.swift (circular dep avoidance)
        .testTarget(
            name: "Async Primitives Tests",
            dependencies: [
                "Async Primitives",
                "Async Primitives Test Support",
            ]
        ),

        // MARK: - Test Support
        .target(
            name: "Async Primitives Test Support",
            dependencies: [
                "Async Primitives",
                .product(name: "Buffer Primitives Test Support", package: "swift-buffer-primitives"),
                .product(name: "Queue Primitives Test Support", package: "swift-queue-primitives"),
                .product(name: "Tagged Primitives Test Support", package: "swift-tagged-primitives"),
            ],
            path: "Tests/Support"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = [
        .enableExperimentalFeature("RawLayout"),
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
