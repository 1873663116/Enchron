// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "RealityKitContent",
    platforms: [
        .visionOS("27.0"),
        .iOS("27.0"),
        .tvOS("27.0")
    ],
    products: [
        .library(
            name: "RealityKitContent",
            targets: ["RealityKitContent"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RealityKitContent",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility")
            ]),
    ]
)
