// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "XrPlayerCoreTestsSupport",
    platforms: [
        .macOS("27.0")
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
            path: "XrPlayer",
            sources: [
                "PlaybackModel/Domain/PlaybackModel.swift",
                "PlaybackModel/Domain/ValueObjects/PlaybackPosition.swift",
                "PlaybackModel/Domain/ValueObjects/MediaProfile.swift",
                "PlaybackModel/Domain/ValueObjects/HDRType.swift",
                "PlaybackModel/Domain/ValueObjects/PlaybackSpeed.swift",
                "PlaybackModel/Domain/ValueObjects/ProjectionType.swift",
                "PlaybackModel/Domain/Entities/PlaybackMediaFile.swift",
                "PlaybackModel/Domain/Entities/AudioTrack.swift",
                "PlaybackModel/Domain/Entities/SubtitleTrack.swift",
                "PlaybackModel/Domain/Events/PlaybackEvents.swift",
                "PlaybackModel/Domain/Ports/PlaybackEventListening.swift",
                "PlaybackModel/Domain/Ports/MediaProfileDetecting.swift",
                "FileBrowsing/Domain/ValueObjects/SourceType.swift",
                "FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift",
                "FileBrowsing/Domain/ValueObjects/FileFilter.swift",
                "FileBrowsing/Domain/ValueObjects/SortCriteria.swift",
                "FileBrowsing/Domain/Entities/BrowsingMediaFile.swift",
                "FileBrowsing/Domain/Entities/DataSource.swift",
                "FileBrowsing/Domain/Entities/MediaFolder.swift",
                "FileBrowsing/Domain/Entities/MediaLibrary.swift",
                "FileBrowsing/Domain/Ports/FileProviding.swift",
                "FileBrowsing/Domain/Ports/DataSourceConnecting.swift",
                "FileBrowsing/Domain/Ports/LocalFileSource.swift",
                "FileBrowsing/Adapters/Local/LocalDataSourceAdapter.swift",
                "FileBrowsing/Adapters/Local/SecurityScopedFileReferenceResolver.swift",
                "FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift",
                "FileBrowsing/Adapters/SMB/SMBDataSourceAdapter.swift",
                "FileBrowsing/Services/HTTPRangeStreamingServer.swift",
                "Persistence/Domain/Ports/CredentialStoring.swift",
                "Persistence/Adapters/KeychainStore.swift",
                "PlayerUI/UseCases/PlaybackTimeFormatter.swift",
                "SpatialScene/Domain/SpatialSceneDomain.swift",
                "SpatialScene/Domain/EnvironmentSceneMapping.swift",
                "SpatialScene/Domain/CinemaEnvironment.swift",
                "PlaybackModel/Domain/ValueObjects/StereoLayout.swift",
                "App/PlaybackSourceAccess.swift",
                "Persistence/Domain/ValueObjects/FileIdentifier.swift",
                "Persistence/Domain/ValueObjects/ProgressPosition.swift",
                "Persistence/Domain/Entities/PlaybackProgress.swift",
                "Persistence/Domain/Entities/SavedScreenPosition.swift",
                "Persistence/Domain/Ports/ProgressStoring.swift",
                "Persistence/Domain/Ports/ScreenPositionStoring.swift",
                "Persistence/Adapters/SwiftDataStore.swift",
                "PlayerUI/Domain/ValueObjects/PlaybackPresentation.swift",
                "PlayerUI/Domain/WindowPlaybackPageGeometry.swift",
                "Shared/DesignSystem/DesignTokens.swift",
                "Persistence/Domain/ValueObjects/ResumePolicy.swift",
                "Persistence/Domain/ValueObjects/PlaybackEndBehavior.swift",
                "Persistence/Domain/Entities/UserPreferences.swift",
                "Persistence/Adapters/UserDefaultsStore.swift",
                "Persistence/Adapters/UserDefaultsMediaLibraryStore.swift",
                "Persistence/Domain/Ports/PreferencesStoring.swift",
                "Persistence/Adapters/Fake/FakePreferencesStore.swift",
                "FileBrowsing/Adapters/Fake/FakeFileDataSource.swift"
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
