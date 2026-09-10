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
        .executable(
            name: "PlaybackCoreRemoteMediaProbe",
            targets: ["PlaybackCoreRemoteMediaProbe"]
        ),
    ],
    targets: [
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
            dependencies: ["PlaybackFFmpeg", "PlaybackSubtitleRenderer"],
            path: "Sources/PlaybackFFmpegBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-O2"], .when(configuration: .debug)),
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
            dependencies: ["PlaybackFFmpegBridge"],
            path: "Sources/PlaybackCore"
        ),
        .executableTarget(
            name: "PlaybackCoreRemoteMediaProbe",
            dependencies: ["PlaybackFFmpegBridge"],
            path: "Tools/RemoteMediaProbe"
        ),
        .testTarget(
            name: "PlaybackCoreTests",
            dependencies: ["PlaybackCore", "PlaybackFFmpegBridge"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
