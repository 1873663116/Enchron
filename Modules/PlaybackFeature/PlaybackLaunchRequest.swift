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
    public let lastUpdatedAt: Date

    public init(
        mediaProfile: PlaybackModel.MediaProfile? = nil,
        fileSizeInBytes: Int64? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.mediaProfile = mediaProfile
        self.fileSizeInBytes = fileSizeInBytes
        self.lastUpdatedAt = lastUpdatedAt
    }

    public func merging(with newer: PlaybackMediaMetadata?) -> PlaybackMediaMetadata {
        guard let newer else { return self }
        return PlaybackMediaMetadata(
            mediaProfile: newer.mediaProfile ?? mediaProfile,
            fileSizeInBytes: newer.fileSizeInBytes ?? fileSizeInBytes,
            lastUpdatedAt: max(lastUpdatedAt, newer.lastUpdatedAt)
        )
    }

    public func updating(mediaProfile: PlaybackModel.MediaProfile) -> PlaybackMediaMetadata {
        PlaybackMediaMetadata(
            mediaProfile: mediaProfile,
            fileSizeInBytes: fileSizeInBytes,
            lastUpdatedAt: Date()
        )
    }
}

public nonisolated struct PlaybackLaunchRequest: @unchecked Sendable, Equatable, Identifiable {
    public let id: URL
    public let url: URL
    public let displayName: String
    public let fileIdentifier: PlaybackFileIdentifier?
    public let initialMetadata: PlaybackMediaMetadata?
    public let collectionOrigin: PlaybackCollectionOrigin
    public let versionedIdentity: VersionedMediaIdentity?
    public let sourceAccess: MediaAccessLease?
    public let externalSubtitleSources: [ResolvedExternalSubtitleSource]
    public let externalSubtitleErrorMessage: String?
    public let viewingStateAuthority: ViewingStateAuthority
    public let startPositionSeconds: Double?
    public let sessionReporter: (any PlaybackSessionReporting)?

    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        externalSubtitleSources: [ResolvedExternalSubtitleSource] = [],
        externalSubtitleErrorMessage: String? = nil,
        viewingStateAuthority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        sessionReporter: (any PlaybackSessionReporting)? = nil
    ) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.sourceAccess = nil
        self.externalSubtitleSources = externalSubtitleSources
        self.externalSubtitleErrorMessage = externalSubtitleErrorMessage
        self.viewingStateAuthority = viewingStateAuthority
        self.startPositionSeconds = startPositionSeconds
        self.sessionReporter = sessionReporter
    }

    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        sourceAccess: MediaAccessLease?,
        externalSubtitleSources: [ResolvedExternalSubtitleSource] = [],
        externalSubtitleErrorMessage: String? = nil,
        viewingStateAuthority: ViewingStateAuthority = .enchronPersistence,
        startPositionSeconds: Double? = nil,
        sessionReporter: (any PlaybackSessionReporting)? = nil
    ) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.sourceAccess = sourceAccess
        self.externalSubtitleSources = externalSubtitleSources
        self.externalSubtitleErrorMessage = externalSubtitleErrorMessage
        self.viewingStateAuthority = viewingStateAuthority
        self.startPositionSeconds = startPositionSeconds
        self.sessionReporter = sessionReporter
    }

    public func updating(metadata: PlaybackMediaMetadata?) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            url: url,
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata?.merging(with: metadata) ?? metadata,
            collectionOrigin: collectionOrigin,
            versionedIdentity: versionedIdentity,
            sourceAccess: sourceAccess,
            externalSubtitleSources: externalSubtitleSources,
            externalSubtitleErrorMessage: externalSubtitleErrorMessage,
            viewingStateAuthority: viewingStateAuthority,
            startPositionSeconds: startPositionSeconds,
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
            lhs.externalSubtitleErrorMessage == rhs.externalSubtitleErrorMessage &&
            lhs.viewingStateAuthority == rhs.viewingStateAuthority &&
            lhs.startPositionSeconds == rhs.startPositionSeconds
    }
}
