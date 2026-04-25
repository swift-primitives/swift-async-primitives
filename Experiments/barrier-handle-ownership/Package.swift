// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "barrier-handle-ownership",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "barrier-handle-ownership",
            swiftSettings: [
                .enableUpcomingFeature("InternalImportsByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableExperimentalFeature("Lifetimes"),
            ]
        )
    ]
)
