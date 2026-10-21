// swift-tools-version:5.9
// Pure-Swift chess + speech-understanding core of Blind Chess. The same sources are compiled straight into the
// iOS app target; this package only exists so the core can be built and tested with `swift test` (also on Linux).
import PackageDescription

let package = Package(
    name: "BlindChessCore",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .library(name: "BlindChessCore", targets: ["BlindChessCore"]),
    ],
    targets: [
        .target(
            name: "BlindChessCore",
            path: ".",
            sources: ["Chess/Core", "Speech/Core"]
        ),
        .testTarget(
            name: "BlindChessCoreTests",
            dependencies: ["BlindChessCore"],
            path: "Tests/BlindChessCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
