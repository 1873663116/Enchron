import Foundation
import MediaSource
import Synchronization
import Testing
@testable import MediaServer

struct EmbyServerStoreTests {
    @Test("service credentials remain isolated even for identical server and user identifiers")
    func serviceIsolation() throws {
        let credentials = InMemoryCredentialStore()
        for kind in MediaServerKind.allCases {
            let store = KeychainMediaServerStore(credentials: credentials, sourceID: kind.credentialKey)
            try store.saveServer(.init(kind: kind, id: .init(rawValue: "same"), name: kind.title,
                                       baseAddress: #require(URL(string: "http://example.test")), accessToken: kind.rawValue,
                                       userID: .init(rawValue: "same")))
        }
        try KeychainMediaServerStore(credentials: credentials, sourceID: MediaServerKind.plex.credentialKey).deleteServer()
        let jellyfin = try KeychainMediaServerStore(credentials: credentials, sourceID: MediaServerKind.jellyfin.credentialKey).loadServer()
        let emby = try KeychainMediaServerStore(credentials: credentials, sourceID: MediaServerKind.emby.credentialKey).loadServer()
        #expect(jellyfin?.kind == .jellyfin)
        #expect(jellyfin?.accessToken == "jellyfin")
        #expect(emby?.accessToken == "emby")
    }

    @Test("the keychain adapter round-trips address, user, and token")
    func roundTrip() throws {
        let credentials = InMemoryCredentialStore()
        let store = KeychainMediaServerStore(credentials: credentials, sourceID: "test-emby")
        let server = MediaServerAuthenticatedServer(
            id: MediaServerServerID(rawValue: "server"),
            name: "Living Room",
            baseAddress: URL(string: "http://example.test:8096")!,
            accessToken: "access-token",
            userID: MediaServerUserID(rawValue: "user")
        )

        try store.saveServer(server)

        #expect(try store.loadServer() == server)
        #expect(credentials.credential(for: "test-emby")?.username == "http://example.test:8096")
        #expect(credentials.credential(for: "test-emby")?.password.contains("access-token") == true)

        try store.deleteServer()
        #expect(try store.loadServer() == nil)
    }
}

private final class InMemoryCredentialStore: CredentialStoring, Sendable {
    private let values = Mutex<[String: StorageCredential]>([:])

    func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        values.withLock { $0[sourceID] = credential }
    }

    func loadCredential(for sourceID: String) throws -> StorageCredential? {
        values.withLock { $0[sourceID] }
    }

    func deleteCredential(for sourceID: String) throws {
        values.withLock { _ = $0.removeValue(forKey: sourceID) }
    }

    func credential(for sourceID: String) -> StorageCredential? {
        values.withLock { $0[sourceID] }
    }
}
