import Foundation
import MediaSource
import Synchronization
import Testing
@testable import Emby

struct EmbyServerStoreTests {
    @Test("the keychain adapter round-trips address, user, and token")
    func roundTrip() throws {
        let credentials = InMemoryCredentialStore()
        let store = KeychainEmbyServerStore(credentials: credentials, sourceID: "test-emby")
        let server = EmbyAuthenticatedServer(
            id: EmbyServerID(rawValue: "server"),
            name: "Living Room",
            baseAddress: URL(string: "http://example.test:8096")!,
            accessToken: "access-token",
            userID: EmbyUserID(rawValue: "user")
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
