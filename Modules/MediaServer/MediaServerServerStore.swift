import Foundation
import MediaSource

public protocol MediaServerServerStoring: Sendable {
    func loadServer() throws -> MediaServerAuthenticatedServer?
    func saveServer(_ server: MediaServerAuthenticatedServer) throws
    func deleteServer() throws
}

public final class KeychainMediaServerStore: MediaServerServerStoring, Sendable {
    private struct Payload: Codable {
        let kind: MediaServerKind?
        let serverID: String
        let serverName: String
        let userID: String
        let accessToken: String
    }

    private let credentials: any CredentialStoring
    private let sourceID: String

    public init(
        credentials: any CredentialStoring = KeychainStore(),
        sourceID: String = "com.enchron.emby.authenticated-server"
    ) {
        self.credentials = credentials
        self.sourceID = sourceID
    }

    public func loadServer() throws -> MediaServerAuthenticatedServer? {
        guard let stored = try credentials.loadCredential(for: sourceID),
              let address = URL(string: stored.username) else { return nil }
        let payload = try JSONDecoder().decode(Payload.self, from: Data(stored.password.utf8))
        return MediaServerAuthenticatedServer(
            kind: payload.kind ?? .emby,
            id: MediaServerServerID(rawValue: payload.serverID),
            name: payload.serverName,
            baseAddress: address,
            accessToken: payload.accessToken,
            userID: MediaServerUserID(rawValue: payload.userID)
        )
    }

    public func saveServer(_ server: MediaServerAuthenticatedServer) throws {
        let payload = Payload(
            kind: server.kind,
            serverID: server.id.rawValue,
            serverName: server.name,
            userID: server.userID.rawValue,
            accessToken: server.accessToken
        )
        let data = try JSONEncoder().encode(payload)
        try credentials.saveCredential(
            for: sourceID,
            credential: StorageCredential(
                username: server.baseAddress.absoluteString,
                password: String(decoding: data, as: UTF8.self)
            )
        )
    }

    public func deleteServer() throws {
        try credentials.deleteCredential(for: sourceID)
    }
}
