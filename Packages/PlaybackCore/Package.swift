// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "PlaybackCore",
    platforms: [
        .visionOS("27.0"),
        /// The module's own tests run here. visionOS is the only platform the product
        /// ships on, but a device run needs a build, an install and a launch, so the
        /// engine's tests would be reached only through the app's test target if this
        /// were dropped, and they are not in it.
        .macOS("27.0"),
    ],
    products: [
        .library(name: "PlaybackCore", targets: ["PlaybackCore"]),
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
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreText"),
                .linkedFramework("Security"),
                .linkedLibrary("c++"),
                .linkedLibrary("hvf"),
                .linkedLibrary("iconv"),
            ]
        ),
        .target(
            name: "PlaybackCore",
            dependencies: ["PlaybackFFmpegBridge"],
            path: "Sources/PlaybackCore"
        ),
        .testTarget(
            name: "PlaybackCoreTests",
            dependencies: ["PlaybackCore", "PlaybackFFmpegBridge"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
