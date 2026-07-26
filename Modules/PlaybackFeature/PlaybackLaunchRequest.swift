import Foundation
import MediaSource

public nonisolated enum PlaybackCollectionOrigin: String, Sendable, Equatable {
    case standalone
    case mediaLibrary
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

    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil
    ) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.sourceAccess = nil
    }

    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        collectionOrigin: PlaybackCollectionOrigin = .standalone,
        versionedIdentity: VersionedMediaIdentity? = nil,
        sourceAccess: MediaAccessLease?
    ) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.sourceAccess = sourceAccess
    }

    public func updating(metadata: PlaybackMediaMetadata?) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            url: url,
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata?.merging(with: metadata) ?? metadata,
            collectionOrigin: collectionOrigin,
            versionedIdentity: versionedIdentity,
            sourceAccess: sourceAccess
        )
    }

    public static func == (lhs: PlaybackLaunchRequest, rhs: PlaybackLaunchRequest) -> Bool {
        lhs.id == rhs.id &&
            lhs.url == rhs.url &&
            lhs.displayName == rhs.displayName &&
            lhs.fileIdentifier == rhs.fileIdentifier &&
            lhs.initialMetadata == rhs.initialMetadata &&
            lhs.collectionOrigin == rhs.collectionOrigin &&
            lhs.versionedIdentity == rhs.versionedIdentity
    }
}
