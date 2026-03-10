import Foundation

public struct PlaybackMediaMetadata: Sendable, Equatable, Codable {
    public let mediaProfile: PlaybackCoreDomain.MediaProfile?
    public let fileSizeInBytes: Int64?
    public let lastUpdatedAt: Date

    public init(
        mediaProfile: PlaybackCoreDomain.MediaProfile? = nil,
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

    public func updating(mediaProfile: PlaybackCoreDomain.MediaProfile) -> PlaybackMediaMetadata {
        PlaybackMediaMetadata(
            mediaProfile: mediaProfile,
            fileSizeInBytes: fileSizeInBytes,
            lastUpdatedAt: Date()
        )
    }
}

public struct PlaybackLaunchRequest: Sendable, Equatable {
    public let url: URL
    public let displayName: String
    public let fileIdentifier: PersistenceDomain.FileIdentifier?
    public let initialMetadata: PlaybackMediaMetadata?

    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PersistenceDomain.FileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil
    ) {
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
    }

    public func updating(metadata: PlaybackMediaMetadata?) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            url: url,
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata?.merging(with: metadata) ?? metadata
        )
    }
}
