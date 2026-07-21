import Foundation
import PlaybackCore

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
    let sourceAccess: PlaybackSourceAccess?

    public init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil
    ) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.sourceAccess = nil
    }

    init(
        url: URL,
        displayName: String,
        fileIdentifier: PlaybackFileIdentifier? = nil,
        initialMetadata: PlaybackMediaMetadata? = nil,
        sourceAccess: PlaybackSourceAccess?
    ) {
        self.id = url
        self.url = url
        self.displayName = displayName
        self.fileIdentifier = fileIdentifier
        self.initialMetadata = initialMetadata
        self.sourceAccess = sourceAccess
    }

    public func updating(metadata: PlaybackMediaMetadata?) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            url: url,
            displayName: displayName,
            fileIdentifier: fileIdentifier,
            initialMetadata: initialMetadata?.merging(with: metadata) ?? metadata,
            sourceAccess: sourceAccess
        )
    }

    public static func == (lhs: PlaybackLaunchRequest, rhs: PlaybackLaunchRequest) -> Bool {
        lhs.id == rhs.id &&
            lhs.url == rhs.url &&
            lhs.displayName == rhs.displayName &&
            lhs.fileIdentifier == rhs.fileIdentifier &&
            lhs.initialMetadata == rhs.initialMetadata
    }
}
