import Foundation
@testable import MediaLibrary
import MediaSource
import XCTest
@testable import EnchronMacOS

nonisolated final class FileBrowsingStartupAccessTests: XCTestCase {
    @MainActor
    func testInitializationDoesNotConnectToAnyLocalFolder() async throws {
        let localSource = LocalAccessSpy()

        let viewModel = FileBrowsingViewModel(
            localDataSource: localSource,
            credentialStore: StartupCredentialStore(),
            savedDataSourceStore: StartupSavedDataSourceStore(),
            onPlayFile: { _ in }
        )

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(localSource.connectedRootPaths, [])
        withExtendedLifetime(viewModel) {}
    }
}

private nonisolated final class LocalAccessSpy: LocalFileSource, @unchecked Sendable {
    private let lock = NSLock()
    private var rootPaths: [String] = []

    var ownerDataSourceID = UUID()
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

    var connectedRootPaths: [String] {
        lock.withLock { rootPaths }
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        lock.withLock { rootPaths.append(info.rootPath) }
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

private nonisolated final class StartupCredentialStore: CredentialStoring, @unchecked Sendable {
    func saveCredential(for sourceID: String, credential: StorageCredential) throws {}
    func loadCredential(for sourceID: String) throws -> StorageCredential? { nil }
    func deleteCredential(for sourceID: String) throws {}
}

private nonisolated final class StartupSavedDataSourceStore:
    SavedDataSourceRecordStoring,
    @unchecked Sendable
{
    func loadSavedDataSourceRecords() -> Data? { nil }
    func saveSavedDataSourceRecords(_ data: Data?) {}
}
