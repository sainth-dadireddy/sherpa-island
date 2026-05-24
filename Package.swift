// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SherpaIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SherpaIsland",
            path: "Sources/SherpaIsland"
        )
    ]
)
