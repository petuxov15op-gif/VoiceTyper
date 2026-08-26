// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceTyper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoiceTyper", targets: ["VoiceTyper"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            from: "1.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceTyper",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .testTarget(name: "VoiceTyperTests", dependencies: ["VoiceTyper"])
    ]
)
