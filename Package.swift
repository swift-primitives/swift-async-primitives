// swift-tools-version: 6.2

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
        .library(
            name: "Async Primitives",
            targets: ["Async Primitives"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-container-primitives"),
        .package(path: "../swift-identity-primitives"),
        .package(path: "../swift-test-support-primitives"),
    ],
    targets: [
        .target(
            name: "Async Primitives",
            dependencies: [
                .product(name: "Container Primitives", package: "swift-container-primitives"),
                .product(name: "Identity Primitives", package: "swift-identity-primitives"),
            ]
        ),
        .testTarget(
            name: "Async Primitives Tests",
            dependencies: [
                "Async Primitives",
                .product(name: "Test Support Primitives", package: "swift-test-support-primitives"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
