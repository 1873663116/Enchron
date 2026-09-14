// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EnvironmentSceneContract",
    platforms: [
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "EnvironmentSceneContract", targets: ["EnvironmentSceneContract"]),
    ],
    targets: [
        .target(
            name: "EnvironmentSceneContract",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
