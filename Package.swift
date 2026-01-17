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
        .package(path: "../swift-kernel-primitives"),
        .package(path: "../swift-reference-primitives"),
        // Test dependencies moved to nested Tests/Package.swift
    ],
    targets: [
        .target(
            name: "Async Primitives",
            dependencies: [
                .product(name: "Buffer Primitives", package: "swift-buffer-primitives"),
                .product(name: "Container Primitives", package: "swift-container-primitives"),
                .product(name: "Identity Primitives", package: "swift-identity-primitives"),
                .product(
                    name: "Kernel Primitives",
                    package: "swift-kernel-primitives",
                    condition: .when(platforms: [
                        .macOS, .iOS, .tvOS, .watchOS, .visionOS,
                        .linux, .windows, .android, .openbsd,
                    ])
                ),
                .product(name: "Reference Primitives", package: "swift-reference-primitives"),
            ]
        ),
        // Tests are in a separate nested package (Tests/Package.swift)
        // to break the circular dependency with swift-testing
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let settings: [SwiftSetting] = [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableExperimentalFeature("Lifetimes"),
        .strictMemorySafety(),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + settings
}
