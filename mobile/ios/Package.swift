// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HerdrMobile", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "MobileCore", targets: ["MobileCore"])], targets: [.target(name: "MobileCore"), .testTarget(name: "MobileCoreTests", dependencies: ["MobileCore"])])
