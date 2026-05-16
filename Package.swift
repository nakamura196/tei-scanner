// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TEIScanner",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "TEIScanner",
            path: "Sources/TEIScanner"
        ),
        .testTarget(
            name: "TEIScannerTests",
            dependencies: ["TEIScanner"],
            path: "Tests/TEIScannerTests"
        )
    ]
)
