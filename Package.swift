// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RSSReader",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RSSReader"),
        .testTarget(name: "RSSReaderTests", dependencies: ["RSSReader"]),
    ]
)
