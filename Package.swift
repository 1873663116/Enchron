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
    dependencies: [
        .package(url: "https://github.com/amosavian/AMSMB2.git", from: "4.0.3")
    ],
    targets: [
        .target(
            name: "XrPlayerCore",
            dependencies: [
                .product(name: "AMSMB2", package: "AMSMB2")
            ],
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
                "XrPlayer/FileBrowsing/Adapters/Local/LocalDataSourceAdapter.swift",
                "XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift",
                "XrPlayer/FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift",
                "XrPlayer/Persistence/Domain/Ports/CredentialStoring.swift",
                "XrPlayer/Persistence/Adapters/KeychainStore.swift",
                "XrPlayer/PlayerUI/Domain/ValueObjects/GestureType.swift",
                "XrPlayer/PlayerUI/UseCases/DisambiguateGestureUseCase.swift",
                "XrPlayer/PlayerUI/UseCases/DetailedTimelineGeometry.swift",
                "XrPlayer/PlayerUI/UseCases/PlaybackTimeFormatter.swift",
                "XrPlayer/PlaybackCore/Adapters/MPV/MPVConfiguration.swift",
                "XrPlayer/PlaybackCore/Adapters/MPV/VideoToolboxBridge.swift",
                "XrPlayer/PlaybackCore/Adapters/MPV/EDRMetadataDescriptor.swift"
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("CoreVideo")
            ]
        ),
        .testTarget(
            name: "XrPlayerCoreTests",
            dependencies: ["XrPlayerCore"],
            path: "Tests/XrPlayerCoreTests"
        )
    ]
)
