// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "inout-noncopyable-optional-closure-capture",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../../swift-ownership-primitives"),
    ],
    targets: [
        .executableTarget(
            name: "inout-noncopyable-optional-closure-capture",
            dependencies: [
                .product(name: "Ownership Primitives", package: "swift-ownership-primitives"),
            ]
        )
    ]
)
