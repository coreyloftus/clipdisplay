// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipDisplay",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClipDisplay",
            path: "Sources/ClipDisplay"
        )
    ],
    swiftLanguageVersions: [.v5]
)
