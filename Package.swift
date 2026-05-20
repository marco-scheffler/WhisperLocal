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
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "WhisperLocal",
            dependencies: [
                "HotKey",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(
            name: "WhisperLocalTests",
            dependencies: ["WhisperLocal"],
            path: "Tests/WhisperLocalTests"
        ),
    ]
)
