// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OceanEnvironment",
    platforms: [
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "OceanEnvironment", targets: ["OceanEnvironment"]),
    ],
    dependencies: [
        .package(path: "../EnvironmentSceneContract"),
    ],
    targets: [
        .target(
            name: "OceanEnvironment",
            dependencies: [
                .product(name: "EnvironmentSceneContract", package: "EnvironmentSceneContract"),
            ],
            resources: [
                .copy("Resources/ocean.reality"),
            ]
        ),
    ]
)
