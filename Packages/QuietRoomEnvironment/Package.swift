// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "QuietRoomEnvironment",
    platforms: [
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "QuietRoomEnvironment", targets: ["QuietRoomEnvironment"]),
    ],
    dependencies: [
        .package(path: "../EnvironmentSceneContract"),
    ],
    targets: [
        .target(
            name: "QuietRoomEnvironment",
            dependencies: [
                .product(name: "EnvironmentSceneContract", package: "EnvironmentSceneContract"),
            ],
            resources: [
                .copy("Resources/quiet_room.reality"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
