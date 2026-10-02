// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "PlaybackCore",
    platforms: [
        .visionOS("27.0"),
        .macOS("27.0"),
    ],
    products: [
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
        .library(name: "BluRayDisc", targets: ["BluRayDisc"]),
        .library(name: "BluRayDiscBridge", targets: ["BluRayDiscBridge"]),
        .executable(name: "BluRayDiscProbe", targets: ["BluRayDiscProbe"]),
        .executable(
            name: "PlaybackCoreRemoteMediaProbe",
            targets: ["PlaybackCoreRemoteMediaProbe"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "PlaybackBluRay",
            path: "Vendor/BluRay/PlaybackBluRay.xcframework"
        ),
        .target(
            name: "BluRayDiscBridge",
            dependencies: ["PlaybackBluRay"],
            path: "Sources/BluRayDiscBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedLibrary("iconv"),
            ]
        ),
        .target(
            name: "BluRayDisc",
            dependencies: ["BluRayDiscBridge"],
            path: "Sources/BluRayDisc"
        ),
        .executableTarget(
            name: "BluRayDiscProbe",
            dependencies: ["BluRayDisc", "BluRayDiscBridge"],
            path: "Tools/BluRayDiscProbe"
        ),
        .binaryTarget(
            name: "PlaybackFFmpeg",
            path: "Vendor/FFmpeg/PlaybackFFmpeg.xcframework"
        ),
        .binaryTarget(
            name: "PlaybackSubtitleRenderer",
            path: "Vendor/SubtitleRenderer/PlaybackSubtitleRenderer.xcframework"
        ),
        .target(
            name: "PlaybackFFmpegBridge",
            dependencies: ["PlaybackFFmpeg", "PlaybackSubtitleRenderer", "BluRayDiscBridge"],
            path: "Sources/PlaybackFFmpegBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-O2"], .when(configuration: .debug)),
                .headerSearchPath("ffmpeg-headers"),
            ],
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreText"),
                .linkedFramework("Security"),
                .linkedLibrary("c++"),
                .linkedLibrary("hvf"),
                .linkedLibrary("iconv"),
                .linkedLibrary("z"),
            ]
        ),
        .target(
            name: "PlaybackCore",
            dependencies: ["PlaybackFFmpegBridge", "BluRayDisc"],
            path: "Sources/PlaybackCore"
        ),
        .executableTarget(
            name: "PlaybackCoreRemoteMediaProbe",
            dependencies: ["PlaybackFFmpegBridge", "BluRayDisc"],
            path: "Tools/RemoteMediaProbe"
        ),
        .testTarget(
            name: "PlaybackCoreTests",
            dependencies: ["PlaybackCore", "PlaybackFFmpegBridge"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "PlaybackCoreStandaloneTests",
            dependencies: ["PlaybackCore"],
            path: "Tests/Standalone"
        ),
        .testTarget(
            name: "BluRayDiscTests",
            dependencies: ["BluRayDisc", "BluRayDiscBridge"],
            path: "Tests/BluRayDiscTests"
        ),
    ]
)
