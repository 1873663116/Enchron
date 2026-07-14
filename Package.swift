// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PlaybackCore",
    platforms: [
        .macOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
    ],
    targets: [
        .binaryTarget(
            name: "PlaybackFFmpeg",
            path: "Vendor/FFmpeg/PlaybackFFmpeg.xcframework"
        ),
        .target(
            name: "PlaybackFFmpegBridge",
            dependencies: ["PlaybackFFmpeg"],
            path: "Sources/PlaybackFFmpegBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
            ]
        ),
        .target(
            name: "PlaybackCore",
            dependencies: ["PlaybackFFmpegBridge"],
            path: "Sources/PlaybackCore"
        ),
        .testTarget(
            name: "PlaybackCoreTests",
            dependencies: ["PlaybackCore", "PlaybackFFmpegBridge"]
        ),
    ]
)
