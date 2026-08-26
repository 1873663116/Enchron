// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "EnchronModules",
    platforms: [
        .visionOS("27.0"),
    ],
    products: [
        .library(name: "MediaSource", targets: ["MediaSource"]),
        .library(name: "Emby", targets: ["Emby"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "MediaLibrary", targets: ["MediaLibrary"]),
        .library(name: "Playback", targets: ["Playback"]),
        .executable(name: "EnchronDomainChecks", targets: ["EnchronDomainChecks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "4.0.3"),
        .package(path: "Packages/PlaybackCore"),
        .package(path: "Packages/RealityKitContent"),
        .package(url: "https://github.com/apple/realitykitscripting.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MediaSource",
            path: "Modules/MediaSource"
        ),
        .target(
            name: "Emby",
            dependencies: ["MediaSource", "DesignSystem", "Playback"],
            path: "Modules/Emby"
        ),
        .target(
            name: "DesignSystem",
            path: "Modules/DesignSystem"
        ),
        .target(
            name: "MediaLibrary",
            dependencies: [
                "MediaSource",
                "DesignSystem",
                .product(name: "AMSMB2", package: "AMSMB2"),
            ],
            path: "Modules/MediaLibrary"
        ),
        .target(
            name: "Playback",
            dependencies: [
                "MediaSource",
                "DesignSystem",
                .product(name: "PlaybackCore", package: "PlaybackCore"),
                .product(name: "RealityKitContent", package: "RealityKitContent"),
                .product(name: "RealityKitScripting", package: "realitykitscripting"),
            ],
            path: "Modules/Playback",
            exclude: [
                "Resources",
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
            ]
        ),
        .executableTarget(
            name: "EnchronDomainChecks",
            dependencies: ["MediaSource", "MediaLibrary", "Playback"],
            path: "Scripts/domain-checks"
        ),
        .testTarget(
            name: "MediaLibraryTests",
            dependencies: ["MediaLibrary"],
            path: "Tests/MediaLibraryPackageTests"
        ),
        .testTarget(
            name: "EmbyTests",
            dependencies: ["Emby", "MediaSource", "Playback", "DesignSystem"],
            path: "Tests/EmbyPackageTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
        .testTarget(
            name: "PlaybackFeatureTests",
            dependencies: ["Playback", "MediaSource"],
            path: "Tests/PlaybackFeaturePackageTests"
        ),
    ]
)
