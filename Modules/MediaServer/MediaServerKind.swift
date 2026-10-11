import Foundation

public enum MediaServerKind: String, Codable, CaseIterable, Sendable {
    case emby
    case jellyfin
    case plex

    public var title: String {
        switch self {
        case .emby: "Emby"
        case .jellyfin: "Jellyfin"
        case .plex: "Plex"
        }
    }

    public var credentialKey: String { "com.enchron.\(rawValue).authenticated-server" }
}

public enum MediaBrowserDialect: Sendable {
    case emby
    case jellyfin
}

public enum MediaServerLogin: Sendable {
    case password(address: URL, username: String, password: String)
    case plexToken(address: URL, token: String, userID: String)
}

public struct MediaServerCapabilities: Sendable {
    public let nextUp: Bool
    public let specialFeatures: Bool
    public let similarItems: Bool

    public static let all = Self(nextUp: true, specialFeatures: true, similarItems: true)
}
