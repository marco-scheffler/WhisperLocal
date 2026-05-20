// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WhisperLocal",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WhisperLocal", targets: ["WhisperLocal"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        // mlx-swift-examples and WhisperKit will be added in Task 7
    ],
    targets: [
        .executableTarget(
            name: "WhisperLocal",
            dependencies: [
                "HotKey",
            ]
        ),
        .testTarget(
            name: "WhisperLocalTests",
            dependencies: ["WhisperLocal"],
            path: "Tests/WhisperLocalTests"
        ),
    ]
)
