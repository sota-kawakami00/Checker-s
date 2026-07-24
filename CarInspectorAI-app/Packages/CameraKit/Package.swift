// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CameraKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CameraKit", targets: ["CameraKit"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "CameraKit",
            dependencies: ["Core"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CameraKitTests", dependencies: ["CameraKit"])
    ]
)
