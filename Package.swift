// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Browspick",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BrowspickCore",
            path: "Sources/BrowspickCore"
        ),
        .executableTarget(
            name: "Browspick",
            dependencies: ["BrowspickCore"],
            path: "Sources/Browspick"
        ),
        // Command Line Tools lacks XCTest and the swift-testing macro plugin,
        // so checks run as a plain executable instead: `swift run CoreChecks`.
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["BrowspickCore"],
            path: "Tests/CoreChecks"
        ),
    ]
)
