// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [.macOS(.v15)],
    dependencies: [
        // TODO: Add WhisperKit dependency once it supports macOS 26 SDK
        // .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            path: "Sources"
        ),
    ]
)
