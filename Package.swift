// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EnchronModules",
    platforms: [
        .macOS("27.0"),
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "MediaSource", targets: ["MediaSource"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "MediaLibrary", targets: ["MediaLibrary"]),
        .library(name: "PlaybackFeature", targets: ["PlaybackFeature"]),
        .library(name: "PlaybackPresentation", targets: ["PlaybackPresentation"]),
        .executable(name: "EnchronDomainChecks", targets: ["EnchronDomainChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "4.0.3"),
    ],
    targets: [
        .target(
            name: "MediaSource",
            path: "Modules/MediaSource"
        ),
        .target(
            name: "DesignSystem",
            path: "Modules/DesignSystem"
        ),
        .target(
            name: "MediaLibrary",
            dependencies: [
                "MediaSource",
                .product(name: "AMSMB2", package: "AMSMB2"),
            ],
            path: "Modules/MediaLibrary",
            exclude: ["Views"]
        ),
        .target(
            name: "PlaybackFeature",
            dependencies: ["MediaSource"],
            path: "Modules/PlaybackFeature",
            exclude: [
                "PlaybackRuntime.swift",
            ]
        ),
        .target(
            name: "PlaybackPresentation",
            dependencies: ["PlaybackFeature"],
            path: "Modules/PlaybackPresentation",
            exclude: [
                "Platform",
                "Resources",
                "Scenes",
                "Views",
            ]
        ),
        .executableTarget(
            name: "EnchronDomainChecks",
            dependencies: ["MediaSource", "MediaLibrary", "PlaybackFeature", "PlaybackPresentation"],
            path: "Scripts/domain-checks"
        ),
    ]
)
