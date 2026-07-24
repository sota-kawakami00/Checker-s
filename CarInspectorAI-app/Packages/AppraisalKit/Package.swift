// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppraisalKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "AppraisalKit", targets: ["AppraisalKit"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "AppraisalKit",
            dependencies: ["Core"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AppraisalKitTests",
            dependencies: ["AppraisalKit"],
            resources: [.process("Fixtures")]
        )
    ]
)
