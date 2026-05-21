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
        .library(
            name: "SwiftTTSWrapperSherpaOnnx",
            targets: ["SwiftTTSWrapperSherpaOnnx"]),
    ],
    dependencies: [
        .package(url: "https://github.com/willwade/sherpa-onnx-spm.git", from: "1.13.3"),
    ],
    targets: [
        .target(
            name: "SwiftTTSWrapper",
            dependencies: [],
            resources: [
                .process("Resources")
            ]),
        .target(
            name: "SwiftTTSWrapperSherpaOnnx",
            dependencies: [
                "SwiftTTSWrapper",
                .product(name: "SherpaOnnx", package: "sherpa-onnx-spm"),
            ]),
        .testTarget(
            name: "SwiftTTSWrapperTests",
            dependencies: ["SwiftTTSWrapper"]),
    ]
)
