// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SyncKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SyncKit", targets: ["SyncKit"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../AppraisalKit")
    ],
    targets: [
        .target(
            name: "SyncKit",
            dependencies: ["Core", "AppraisalKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SyncKitTests", dependencies: ["SyncKit"])
    ]
)
