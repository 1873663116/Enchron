import Foundation
@testable import MediaLibrary
import MediaSource
import XCTest
@testable import EnchronMacOS

nonisolated final class RemoteCredentialLifecycleTests: XCTestCase {
    @MainActor
    func testConnectionCredentialIsAnUncommittedOverlay() async throws {
        let persistentStore = InMemoryCredentialStore()
        let source = try makeSMBSource(share: "Movies")
        try persistentStore.saveCredential(
            for: source.credentialSourceID,
            credential: .init(username: "existing", password: "old-secret")
        )
        var adapter: CredentialReadingRemoteAdapter?
        let viewModel = makeViewModel(
            credentialStore: persistentStore,
            makeRemoteAdapter: { dataSource, credentialStore in
                let created = CredentialReadingRemoteAdapter(
                    sourceID: dataSource.credentialSourceID,
                    credentialStore: credentialStore
                )
                adapter = created
                return created
            }
        )

        let proposed = StorageCredential(username: "candidate", password: "new-secret")
        await viewModel.connectToDataSource(source, credential: proposed)

        XCTAssertEqual(adapter?.observedCredential, proposed)
        XCTAssertEqual(
            try persistentStore.loadCredential(for: source.credentialSourceID),
            .init(username: "existing", password: "old-secret")
        )
        XCTAssertEqual(viewModel.activeDataSource?.id, source.id)
    }

    @MainActor
    func testRemovingOneSMBShareKeepsHostCredentialUntilLastShareIsRemoved() throws {
        let persistentStore = InMemoryCredentialStore()
        let movies = try makeSMBSource(share: "Movies")
        let television = try makeSMBSource(share: "Television")
        XCTAssertEqual(movies.credentialSourceID, television.credentialSourceID)
        try persistentStore.saveCredential(
            for: movies.credentialSourceID,
            credential: .init(username: "viewer", password: "secret")
        )
        let viewModel = makeViewModel(credentialStore: persistentStore)
        viewModel.addDataSource(movies)
        viewModel.addDataSource(television)

        viewModel.removeDataSource(id: movies.id)
        XCTAssertNotNil(try persistentStore.loadCredential(for: movies.credentialSourceID))

        viewModel.removeDataSource(id: television.id)
        XCTAssertNil(try persistentStore.loadCredential(for: movies.credentialSourceID))
        XCTAssertEqual(persistentStore.deletedSourceIDs, [movies.credentialSourceID])
    }

    @MainActor
    func testLegacyHostCredentialMigratesIntoTheAccountNamespace() throws {
        let persistentStore = InMemoryCredentialStore()
        let source = try makeSMBSource(share: "Movies")
        let legacySourceID = source.connectionInfo.legacyCredentialSourceID
        let credential = StorageCredential(username: "viewer", password: "secret")
        try persistentStore.saveCredential(for: legacySourceID, credential: credential)

        XCTAssertEqual(
            try persistentStore.loadCredential(for: source.connectionInfo),
            credential
        )
        XCTAssertEqual(
            try persistentStore.loadCredential(for: source.credentialSourceID),
            credential
        )
        XCTAssertNil(try persistentStore.loadCredential(for: legacySourceID))
    }

    @MainActor
    func testGuestDoesNotMigrateAnotherAccountsLegacyCredential() throws {
        let persistentStore = InMemoryCredentialStore()
        let connection = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.168.1.20"
        ).withSMBShare("Movies")
        let legacySourceID = connection.legacyCredentialSourceID
        let otherAccount = StorageCredential(username: "viewer", password: "secret")
        try persistentStore.saveCredential(for: legacySourceID, credential: otherAccount)

        XCTAssertNil(try persistentStore.loadCredential(for: connection))
        XCTAssertNil(try persistentStore.loadCredential(for: connection.credentialSourceID))
        XCTAssertEqual(try persistentStore.loadCredential(for: legacySourceID), otherAccount)
    }

    @MainActor
    func testGuestMigratesItsCompatibleLegacyCredential() throws {
        let persistentStore = InMemoryCredentialStore()
        let connection = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.168.1.20"
        ).withSMBShare("Movies")
        let legacySourceID = connection.legacyCredentialSourceID
        let guest = StorageCredential(username: "guest", password: "")
        try persistentStore.saveCredential(for: legacySourceID, credential: guest)

        XCTAssertEqual(try persistentStore.loadCredential(for: connection), guest)
        XCTAssertEqual(try persistentStore.loadCredential(for: connection.credentialSourceID), guest)
        XCTAssertNil(try persistentStore.loadCredential(for: legacySourceID))
    }

    @MainActor
    private func makeViewModel(
        credentialStore: InMemoryCredentialStore,
        makeRemoteAdapter: (@MainActor (
            FileBrowsingDomain.DataSource,
            any CredentialStoring
        ) -> (any DataSourceConnecting & FileProviding)?)? = nil
    ) -> FileBrowsingViewModel {
        FileBrowsingViewModel(
            localDataSource: FakeFileDataSource(),
            credentialStore: credentialStore,
            savedDataSourceStore: InMemorySavedDataSourceStore(),
            makeRemoteAdapter: makeRemoteAdapter,
            onPlayFile: { _ in }
        )
    }

    private func makeSMBSource(
        share: String
    ) throws -> FileBrowsingDomain.DataSource {
        let connection = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .smb,
            address: "192.168.1.20",
            username: "viewer"
        ).withSMBShare(share)
        return FileBrowsingDomain.DataSource(
            name: share,
            sourceType: .smb,
            connectionInfo: connection
        )
    }
}

private nonisolated final class CredentialReadingRemoteAdapter:
    DataSourceConnecting,
    FileProviding,
    @unchecked Sendable
{
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private let sourceID: String
    private let credentialStore: any CredentialStoring
    private(set) var observedCredential: StorageCredential?

    init(sourceID: String, credentialStore: any CredentialStoring) {
        self.sourceID = sourceID
        self.credentialStore = credentialStore
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        observedCredential = try credentialStore.loadCredential(for: sourceID)
        connectionStatus = .connected
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] { [] }
    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] { [] }
    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL { item.url }

    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> ResolvedMediaSource {
        ResolvedMediaSource(url: file.url)
    }
}

private nonisolated final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [String: StorageCredential] = [:]
    private var deleted: [String] = []

    var deletedSourceIDs: [String] {
        lock.withLock { deleted }
    }

    func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        lock.withLock { credentials[sourceID] = credential }
    }

    func loadCredential(for sourceID: String) throws -> StorageCredential? {
        lock.withLock { credentials[sourceID] }
    }

    func deleteCredential(for sourceID: String) throws {
        lock.withLock {
            credentials.removeValue(forKey: sourceID)
            deleted.append(sourceID)
        }
    }
}

private nonisolated final class InMemorySavedDataSourceStore:
    SavedDataSourceRecordStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var data: Data?

    func loadSavedDataSourceRecords() -> Data? {
        lock.withLock { data }
    }

    func saveSavedDataSourceRecords(_ data: Data?) {
        lock.withLock { self.data = data }
    }
}
