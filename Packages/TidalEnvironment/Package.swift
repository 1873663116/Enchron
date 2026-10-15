// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TidalEnvironment",
    platforms: [
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "TidalEnvironment", targets: ["TidalEnvironment"]),
    ],
    dependencies: [
        .package(path: "../EnvironmentSceneContract"),
    ],
    targets: [
        .target(
            name: "TidalEnvironment",
            dependencies: [
                .product(name: "EnvironmentSceneContract", package: "EnvironmentSceneContract"),
            ],
            resources: [
                .copy("Resources/tidal.reality"),
                .copy("Resources/dark-parameters.bin"),
                .copy("Resources/floor-dark.ktx"),
                .copy("Resources/wall-left-dark.ktx"),
                .copy("Resources/recess-dark.ktx"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
