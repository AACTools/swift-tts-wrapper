// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftTTSWrapper",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SwiftTTSWrapper",
            targets: ["SwiftTTSWrapper"]),
    ],
    targets: [
        .target(
            name: "SwiftTTSWrapper",
            dependencies: [],
            resources: [
                .process("Resources")
            ]),
        .testTarget(
            name: "SwiftTTSWrapperTests",
            dependencies: ["SwiftTTSWrapper"]),
    ]
)
