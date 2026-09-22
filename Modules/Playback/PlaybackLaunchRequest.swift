import Foundation
import MediaSource

public nonisolated enum PlaybackCollectionOrigin: String, Sendable, Equatable {
    case standalone
    case mediaLibrary
    case mediaServer
    case sourceDirectory
}

public nonisolated struct PlaybackFileIdentifier: Sendable, Equatable, Hashable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func make(
        path: String,
        sizeInBytes: Int64,
        serverFingerprint: String?
    ) -> PlaybackFileIdentifier {
        PlaybackFileIdentifier(
            rawValue: "\(path)|\(sizeInBytes)|\(serverFingerprint ?? "local")"
        )
    }
}

public nonisolated struct PlaybackMediaMetadata: Sendable, Equatable, Codable {
    public let mediaProfile: PlaybackModel.MediaProfile?
    public let fileSizeInBytes: Int64?
    public let overview: String?
    public let lastUpdatedAt: Date

    public init(
        mediaProfile: PlaybackModel.MediaProfile? = nil,
        fileSizeInBytes: Int64? = nil,
        overview: String? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.mediaProfile = mediaProfile
        self.fileSizeInBytes = fileSizeInBytes
        self.overview = overview
        self.lastUpdatedAt = lastUpdatedAt
    }

    public func merging(with newer: PlaybackMediaMetadata?) -> PlaybackMediaMetadata {
        guard let newer else { return self }
        return PlaybackMediaMetadata(
            mediaProfile: newer.mediaProfile ?? mediaProfile,
            fileSizeInBytes: newer.fileSizeInBytes ?? fileSizeInBytes,
            overview: newer.overview ?? overview,
            lastUpdatedAt: max(lastUpdatedAt, newer.lastUpdatedAt)
        )
    }

    public func updating(mediaProfile: PlaybackModel.MediaProfile) -> PlaybackMediaMetadata {
        PlaybackMediaMetadata(
            mediaProfile: mediaProfile,
            fileSizeInBytes: fileSizeInBytes,
            overview: overview,
            lastUpdatedAt: Date()
        )
    }
}

public nonisolated struct PlaybackAddress: @unchecked Sendable, Equatable {
    public enum AddressError: LocalizedError {
        case notLocalFile

        public var errorDescription: String? {
            "Only local file URLs can enter playback without a MediaSource byte-stream handle."
        }
    }

    public let url: URL
    public let byteStreamHandle: MediaByteStreamHandle?
    private let remote: Bool

    public init(localFileURL: URL) throws {
        guard localFileURL.isFileURL else { throw AddressError.notLocalFile }
        url = localFileURL
        byteStreamHandle = nil
        remote = false
    }

    public init(byteStreamHandle: MediaByteStreamHandle) {
        url = byteStreamHandle.url
        self.byteStreamHandle = byteStreamHandle
        remote = true
    }

#if DEBUG
    @_spi(Testing)
    public init(testingURL: URL) {
        url = testingURL
        byteStreamHandle = nil
        remote = testingURL.isFileURL == false
    }
#endif

    public var isRemote: Bool { remote }
    public var preferredBufferDepth: MediaByteBufferDepth {
        byteStreamHandle?.preferredBufferDepth ?? (remote ? .automatic : .none)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
    }
}

public nonisolated struct PlaybackLaunchRequest: @unchecked Sendable, Equatable, Identifiable {
    func refreshedLoopbackEndpoints() async -> PlaybackLaunchRequest? {
        guard let mainHandle = source.byteStreamHandle else { return nil }
        let handles = [mainHandle] + externalSubtitleSources.compactMap(\.byteStreamHandle)
        guard let refreshed = try? await MediaByteStreamHandle.refreshing(
            handles, restartingListeners: true
        ) else { return nil }
        var subtitleIndex = 1
        let subtitles = externalSubtitleSources.map { subtitle in
            guard subtitle.byteStreamHandle != nil else { return subtitle }
            let handle = refreshed[subtitleIndex]
            subtitleIndex += 1
            return ResolvedExternalSubtitleSource(
                id: subtitle.id, url: handle.url, displayName: subtitle.displayName,
                versionedIdentity: subtitle.versionedIdentity,
                accessLease: subtitle.accessLease, byteStreamHandle: handle
            )
        }
        return PlaybackLaunchRequest(
            source: PlaybackAddress(byteStreamHandle: refreshed[0]),
            displayName: displayName, fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata, collectionOrigin: collectionOrigin,
            versionedIdentity: versionedIdentity, sourceAccess: sourceAccess,
            externalSubtitleSources: subtitles,
            externalSubtitleResolutionFailed: externalSubtitleResolutionFailed,
            viewingStateAuthority: viewingStateAuthority,
            startPositionSeconds: startPositionSeconds,
            initialTrackSelection: initialTrackSelection, sessionReporter: sessionReporter
        )
    }

    public let id: URL
    public let source: PlaybackAddress
    public var url: URL { source.url }
    public let displayName: String
    public let fileIdentifier: PlaybackFileIdentifier?
    public let initialMetadata: PlaybackMediaMetadata?
    public let collectionOrigin: PlaybackCollectionOrigin
    public let versionedIdentity: VersionedMediaIdentity?
    public let sourceAccess: MediaAccessLease?
    public let externalSubtitleSources: [ResolvedExternalSubtitleSource]
    public let externalSubtitleResolutionFailed: Bool
    public let viewingStateAuthority: ViewingStateAuthority
    public let startPositionSeconds: Double?
    public let initialTrackSelection: TrackSelectionPreference?
    public let sessionReporter: (any PlaybackSessionReporting)?

    public init(
        source: PlaybackAddress,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        externalSubtitleSources: [ResolvedExternalSubtitleSource] = [],
        externalSubtitleResolutionFailed: Bool = false,
        viewingStateAuthority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        initialTrackSelection: TrackSelectionPreference? = nil,
        sessionReporter: (any PlaybackSessionReporting)? = nil
    ) {
        self.id = source.url
        self.source = source
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.sourceAccess = nil
        self.externalSubtitleSources = externalSubtitleSources
        self.externalSubtitleResolutionFailed = externalSubtitleResolutionFailed
        self.viewingStateAuthority = viewingStateAuthority
        self.startPositionSeconds = startPositionSeconds
        self.initialTrackSelection = initialTrackSelection
        self.sessionReporter = sessionReporter
    }

#if DEBUG
    @_spi(Testing)
    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        externalSubtitleSources: [ResolvedExternalSubtitleSource] = [],
        externalSubtitleResolutionFailed: Bool = false,
        viewingStateAuthority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        initialTrackSelection: TrackSelectionPreference? = nil,
        sessionReporter: (any PlaybackSessionReporting)? = nil
    ) {
        self.init(
            source: PlaybackAddress(testingURL: url),
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata,
            collectionOrigin: collectionOrigin,
            versionedIdentity: versionedIdentity,
            externalSubtitleSources: externalSubtitleSources,
            externalSubtitleResolutionFailed: externalSubtitleResolutionFailed,
            viewingStateAuthority: viewingStateAuthority,
            startPositionSeconds: startPositionSeconds,
            initialTrackSelection: initialTrackSelection,
            sessionReporter: sessionReporter
        )
    }
#endif

    public init(
        source: PlaybackAddress,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        sourceAccess: MediaAccessLease?,
        externalSubtitleSources: [ResolvedExternalSubtitleSource] = [],
        externalSubtitleResolutionFailed: Bool = false,
        viewingStateAuthority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        initialTrackSelection: TrackSelectionPreference? = nil,
        sessionReporter: (any PlaybackSessionReporting)? = nil
    ) {
        self.id = source.url
        self.source = source
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.sourceAccess = sourceAccess
        self.externalSubtitleSources = externalSubtitleSources
        self.externalSubtitleResolutionFailed = externalSubtitleResolutionFailed
        self.viewingStateAuthority = viewingStateAuthority
        self.startPositionSeconds = startPositionSeconds
        self.initialTrackSelection = initialTrackSelection
        self.sessionReporter = sessionReporter
    }

#if DEBUG
    @_spi(Testing)
    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        sourceAccess: MediaAccessLease?,
        externalSubtitleSources: [ResolvedExternalSubtitleSource] = [],
        externalSubtitleResolutionFailed: Bool = false,
        viewingStateAuthority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        initialTrackSelection: TrackSelectionPreference? = nil,
        sessionReporter: (any PlaybackSessionReporting)? = nil
    ) {
        self.init(
            source: PlaybackAddress(testingURL: url),
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata,
            collectionOrigin: collectionOrigin,
            versionedIdentity: versionedIdentity,
            sourceAccess: sourceAccess,
            externalSubtitleSources: externalSubtitleSources,
            externalSubtitleResolutionFailed: externalSubtitleResolutionFailed,
            viewingStateAuthority: viewingStateAuthority,
            startPositionSeconds: startPositionSeconds,
            initialTrackSelection: initialTrackSelection,
            sessionReporter: sessionReporter
        )
    }
#endif

    public func updating(metadata: PlaybackMediaMetadata?) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            source: source,
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata?.merging(with: metadata) ?? metadata,
            collectionOrigin: collectionOrigin,
            versionedIdentity: versionedIdentity,
            sourceAccess: sourceAccess,
            externalSubtitleSources: externalSubtitleSources,
            externalSubtitleResolutionFailed: externalSubtitleResolutionFailed,
            viewingStateAuthority: viewingStateAuthority,
            startPositionSeconds: startPositionSeconds,
            initialTrackSelection: initialTrackSelection,
            sessionReporter: sessionReporter
        )
    }

    public static func == (lhs: PlaybackLaunchRequest, rhs: PlaybackLaunchRequest) -> Bool {
        lhs.id == rhs.id &&
            lhs.url == rhs.url &&
            lhs.displayName == rhs.displayName &&
            lhs.fileIdentifier == rhs.fileIdentifier &&
            lhs.initialMetadata == rhs.initialMetadata &&
            lhs.collectionOrigin == rhs.collectionOrigin &&
            lhs.versionedIdentity == rhs.versionedIdentity &&
            lhs.externalSubtitleSources == rhs.externalSubtitleSources &&
            lhs.externalSubtitleResolutionFailed == rhs.externalSubtitleResolutionFailed &&
            lhs.viewingStateAuthority == rhs.viewingStateAuthority &&
            lhs.startPositionSeconds == rhs.startPositionSeconds &&
            lhs.initialTrackSelection == rhs.initialTrackSelection
    }
}
