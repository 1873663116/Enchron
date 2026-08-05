import Foundation

public struct ResolvedExternalSubtitleSource: @unchecked Sendable, Equatable, Identifiable {
    public let id: String
    public let url: URL
    public let displayName: String
    public let versionedIdentity: VersionedMediaIdentity?
    public let accessLease: MediaAccessLease?

    public init(
        id: String,
        url: URL,
        displayName: String,
        versionedIdentity: VersionedMediaIdentity? = nil,
        accessLease: MediaAccessLease? = nil
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName
        self.versionedIdentity = versionedIdentity
        self.accessLease = accessLease
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.url == rhs.url
            && lhs.displayName == rhs.displayName
            && lhs.versionedIdentity == rhs.versionedIdentity
    }
}
