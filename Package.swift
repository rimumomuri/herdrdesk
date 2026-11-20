// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HerdrDesk",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DeskCore", path: "Sources/DeskCore"),
        .executableTarget(name: "HerdrDesk", dependencies: ["DeskCore"], path: "Sources/HerdrDesk"),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"], path: "Tests/DeskCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
