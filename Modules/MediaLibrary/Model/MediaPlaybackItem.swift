import Foundation
import MediaSource

public enum MediaCollectionOrigin: String, Sendable, Equatable {
    case standalone
    case mediaLibrary
    case sourceDirectory
}

public struct MediaPlaybackItem: @unchecked Sendable, Equatable, Identifiable {
    public let id: UUID
    public let url: URL
    public let displayName: String
    public let stableIdentifier: String?
    public let sizeInBytes: Int64?
    public let collectionOrigin: MediaCollectionOrigin
    public let versionedIdentity: VersionedMediaIdentity?
    public let accessLease: MediaAccessLease?

    public init(
        id: UUID,
        url: URL,
        displayName: String,
        stableIdentifier: String? = nil,
        sizeInBytes: Int64? = nil,
        collectionOrigin: MediaCollectionOrigin,
        versionedIdentity: VersionedMediaIdentity? = nil,
        accessLease: MediaAccessLease? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.stableIdentifier = stableIdentifier
        self.sizeInBytes = sizeInBytes
        self.collectionOrigin = collectionOrigin
        self.versionedIdentity = versionedIdentity
        self.accessLease = accessLease
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.url == rhs.url
            && lhs.displayName == rhs.displayName
            && lhs.stableIdentifier == rhs.stableIdentifier
            && lhs.sizeInBytes == rhs.sizeInBytes
            && lhs.collectionOrigin == rhs.collectionOrigin
            && lhs.versionedIdentity == rhs.versionedIdentity
    }
}

public struct MediaCollectionEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let isCurrent: Bool

    public init(id: UUID, displayName: String, isCurrent: Bool) {
        self.id = id
        self.displayName = displayName
        self.isCurrent = isCurrent
    }
}

public struct MediaCollectionSnapshot: Sendable, Equatable {
    public let entries: [MediaCollectionEntry]

    public init(entries: [MediaCollectionEntry]) {
        self.entries = entries
    }

    public static let empty = MediaCollectionSnapshot(entries: [])
}

public struct VideoCardViewingState: Equatable, Sendable {
    public let positionSeconds: Double
    public let durationSeconds: Double
    public let isCompleted: Bool

    public init(positionSeconds: Double, durationSeconds: Double, isCompleted: Bool) {
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
    }

    public var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }
}

public typealias MediaViewingStateProvider = @Sendable (MediaIdentity) async -> VideoCardViewingState?
