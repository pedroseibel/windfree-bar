// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WindFreeBar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "WindFreeBar",
            path: "Sources/WindFreeBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
