// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MediaByteStreamConformance",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(name: "EnchronModules", path: "../.."),
    ],
    targets: [
        .testTarget(
            name: "MediaByteStreamConformanceTests",
            dependencies: [
                .product(name: "MediaSource", package: "EnchronModules"),
            ]
        ),
    ]
)
