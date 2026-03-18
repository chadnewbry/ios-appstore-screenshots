// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotGenerator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "ios-appstore-screenshots",
            targets: ["ScreenshotGenerator"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotGenerator",
            path: "Sources/ScreenshotGenerator"
        )
    ]
)
