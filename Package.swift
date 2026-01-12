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
        .package(path: "../swift-buffer-primitives"),
        .package(path: "../swift-container-primitives"),
        .package(path: "../swift-identity-primitives"),
        .package(path: "../swift-test-primitives"),
        .package(path: "../../swift-foundations/swift-testing-extras"),
    ],
    targets: [
        .target(
            name: "Async Primitives",
            dependencies: [
                .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
                .product(name: "Container Primitives", package: "swift-container-primitives"),
                .product(name: "Identity Primitives", package: "swift-identity-primitives"),
            ]
        ),
        .testTarget(
            name: "Async Primitives Tests",
            dependencies: [
                "Async Primitives",
                .product(name: "Test Primitives", package: "swift-test-primitives"),
                .product(name: "Testing Extras", package: "swift-testing-extras"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
