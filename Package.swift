// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XrPlayerCoreTestsSupport",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "XrPlayerCore", targets: ["XrPlayerCore"])
    ],
    targets: [
        .target(
            name: "XrPlayerCore",
            path: ".",
            sources: [
                "XrPlayer/PlaybackCore/Domain/ValueObjects/PlaybackState.swift",
                "XrPlayer/PlaybackCore/Domain/ValueObjects/PlaybackPosition.swift",
                "XrPlayer/PlaybackCore/Domain/ValueObjects/MediaProfile.swift",
                "XrPlayer/PlaybackCore/Domain/ValueObjects/HDRType.swift",
                "XrPlayer/PlaybackCore/Domain/ValueObjects/PlaybackSpeed.swift",
                "XrPlayer/PlaybackCore/Domain/ValueObjects/ProjectionType.swift",
                "XrPlayer/PlaybackCore/Domain/Entities/PlaybackMediaFile.swift",
                "XrPlayer/PlaybackCore/Domain/Entities/PlaybackSession.swift",
                "XrPlayer/PlaybackCore/Domain/Entities/AudioTrack.swift",
                "XrPlayer/PlaybackCore/Domain/Entities/SubtitleTrack.swift",
                "XrPlayer/PlaybackCore/Domain/Events/PlaybackEvents.swift",
                "XrPlayer/PlaybackCore/Domain/Ports/PlaybackControlling.swift",
                "XrPlayer/PlaybackCore/Domain/Ports/PlaybackEventListening.swift",
                "XrPlayer/PlaybackCore/Domain/Ports/MediaProfileDetecting.swift",
                "XrPlayer/PlaybackCore/Domain/Ports/FrameOutput.swift",
                "XrPlayer/FileBrowsing/Domain/ValueObjects/SourceType.swift",
                "XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift",
                "XrPlayer/FileBrowsing/Domain/ValueObjects/FileFilter.swift",
                "XrPlayer/FileBrowsing/Domain/ValueObjects/SortCriteria.swift",
                "XrPlayer/FileBrowsing/Domain/Entities/BrowsingMediaFile.swift",
                "XrPlayer/FileBrowsing/Domain/Entities/DataSource.swift",
                "XrPlayer/FileBrowsing/Domain/Entities/MediaFolder.swift",
                "XrPlayer/FileBrowsing/Domain/Ports/FileProviding.swift",
                "XrPlayer/FileBrowsing/Domain/Ports/DataSourceConnecting.swift",
                "XrPlayer/FileBrowsing/Adapters/Local/LocalDataSourceAdapter.swift"
            ]
        ),
        .testTarget(
            name: "XrPlayerCoreTests",
            dependencies: ["XrPlayerCore"],
            path: "Tests/XrPlayerCoreTests"
        )
    ]
)
