// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "Sources",
            exclude: ["Resources/AppIcon.appiconset"],
            resources: [.process("Resources")]
        ),
        // Tests need a real Xcode toolchain: the Command Line Tools ship
        // swift-testing but no runner, so `swift test` there exits 0 having
        // executed nothing. Pointing -F at the CLT frameworks (as this target
        // used to) made tests compile without Xcode but also shadowed Xcode's
        // own swift-testing with an older copy, breaking the build wherever
        // Xcode *was* present. Select Xcode with `xcode-select` instead.
        .testTarget(
            name: "MeetingScribeTests",
            dependencies: ["MeetingScribe"],
            path: "Tests"
        ),
    ]
)
