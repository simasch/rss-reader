// swift-tools-version: 6.0
import PackageDescription

/// Platform-independent core of RSS Reader: models, feed parsing and fetching, persistence, OPML.
/// The app UI lives in ../App and is built by ../RSSReader.xcodeproj.
let package = Package(
    name: "RSSReaderKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "RSSReaderKit", targets: ["RSSReaderKit"]),
    ],
    targets: [
        .target(name: "RSSReaderKit"),
        .testTarget(name: "RSSReaderKitTests", dependencies: ["RSSReaderKit"]),
    ]
)
