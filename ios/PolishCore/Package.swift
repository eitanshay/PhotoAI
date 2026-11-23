// swift-tools-version:5.9
// Core logic shared with the iOS app target. The app compiles these same source files directly;
// this package exists so the logic can be unit-tested on any machine (including Linux) with `swift test`.
import PackageDescription

let package = Package(
    name: "PolishCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "PolishCore", targets: ["PolishCore"])],
    targets: [
        .target(name: "PolishCore"),
        .testTarget(name: "PolishCoreTests", dependencies: ["PolishCore"])
    ]
)
