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
        .package(url: "https://github.com/willwade/sherpa-onnx-spm.git", "1.13.4"..<"1.14.0"),
        .package(url: "https://github.com/AACTools/speechmarkdown-rust", from: "0.3.1"),
    ],
    targets: [
        .target(
            name: "SwiftTTSWrapper",
            dependencies: [
                .product(name: "SpeechMarkdown", package: "speechmarkdown-rust"),
            ],
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
