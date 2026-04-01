// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "bridge-push-ownership-conventions",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "bridge-push-ownership-conventions"
        )
    ]
)
