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
        // MARK: - Core
        .library(
            name: "Async Primitives Core",
            targets: ["Async Primitives Core"]
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
        .library(
            name: "Async Timer Primitives",
            targets: ["Async Timer Primitives"]
        ),
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
        .package(url: "https://github.com/swift-primitives/swift-storage-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dictionary-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-dictionary-ordered-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-queue-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-deque-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-tagged-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-ownership-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-link-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-buffer-arena-primitives.git", branch: "main"),
    ],
    targets: [
        // MARK: - Core
        .target(
            name: "Async Primitives Core",
            dependencies: [
                .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
                .product(name: "Queue Primitives", package: "swift-queue-primitives"),
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
                .product(name: "Tagged Primitives", package: "swift-tagged-primitives"),
            ]
        ),

        // MARK: - Mutex
        .target(
            name: "Async Mutex Primitives",
            dependencies: [
                "Async Primitives Core",
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
            ]
        ),

        // MARK: - Coordination
        .target(
            name: "Async Bridge Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
            ]
        ),
        .target(
            name: "Async Promise Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
            ]
        ),
        .target(
            name: "Async Publication Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
            ]
        ),
        .target(
            name: "Async Barrier Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
            ]
        ),
        .target(
            name: "Async Completion Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
            ]
        ),

        // MARK: - Variants
        .target(
            name: "Async Channel Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
                "Async Waiter Primitives",
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
            ]
        ),
        .target(
            name: "Async Broadcast Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
                "Async Publication Primitives",
                .product(name: "Dictionary Primitives", package: "swift-dictionary-primitives"),
                .product(name: "Dictionary Ordered Primitives", package: "swift-dictionary-ordered-primitives"),
                .product(name: "Deque Primitives", package: "swift-deque-primitives"),
            ]
        ),
        .target(
            name: "Async Timer Primitives",
            dependencies: [
                .product(name: "Storage Primitive", package: "swift-storage-primitives"),
                "Async Primitives Core",
                .product(name: "Link Primitives", package: "swift-link-primitives"),
                .product(name: "Buffer Arena Primitive", package: "swift-buffer-arena-primitives"),
                .product(name: "Buffer Arena Bounded Primitive", package: "swift-buffer-arena-primitives"),
            ]
        ),
        .target(
            name: "Async Waiter Primitives",
            dependencies: [
                "Async Primitives Core",
            ]
        ),

        // MARK: - Semaphore
        .target(
            name: "Async Semaphore Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
                "Async Waiter Primitives",
                "Async Promise Primitives",
                .product(name: "Either Primitives", package: "swift-either-primitives"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Async Primitives",
            dependencies: [
                "Async Primitives Core",
                "Async Mutex Primitives",
                "Async Bridge Primitives",
                "Async Promise Primitives",
                "Async Publication Primitives",
                "Async Barrier Primitives",
                "Async Completion Primitives",
                "Async Channel Primitives",
                "Async Broadcast Primitives",
                "Async Timer Primitives",
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
