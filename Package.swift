// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VibeIsland", targets: ["VibeIsland"])
    ],
    targets: [
        .target(name: "VibeIslandShared"),
        .executableTarget(
            name: "VibeIsland",
            dependencies: ["VibeIslandShared"]
        ),
        .testTarget(
            name: "VibeIslandTests",
            dependencies: ["VibeIsland", "VibeIslandShared"]
        )
    ],
    swiftLanguageModes: [.v5]
)
