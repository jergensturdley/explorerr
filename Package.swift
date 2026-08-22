// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Explorerr",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "CSupport",
            path: "Sources/CSupport"
        ),
        .executableTarget(
            name: "Explorerr",
            dependencies: ["CSupport"],
            path: "Sources/Explorerr"
        ),
    ],
    swiftLanguageModes: [.v5]
)
