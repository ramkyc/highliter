// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenHighlighter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ScreenHighlighter", targets: ["ScreenHighlighter"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenHighlighter",
            path: "Sources/ScreenHighlighter"
        ),
        .testTarget(
            name: "ScreenHighlighterTests",
            dependencies: ["ScreenHighlighter"],
            path: "Tests/ScreenHighlighterTests"
        )
    ]
)
