import Foundation
import XCTest
@testable import EnchronMacOS

nonisolated final class RemoteSourceIsolationTests: XCTestCase {
    @MainActor
    func testDismissingRemoteFailureDoesNotExposeLocalDocuments() async throws {
        let localSourceID = UUID()
        let localSource = SourceIsolationLocalSource(ownerDataSourceID: localSourceID)
        let recorder = RemoteInvocationRecorder()
        let remoteSource = try makeWebDAVSource(name: "AList E2E", host: "127.0.0.1")
        let viewModel = makeViewModel(localSource: localSource) { source, _ in
            SourceIsolationRemoteAdapter(
                sourceID: source.id,
                recorder: recorder,
                failure: .listing
            )
        }

        await viewModel.connectToDataSource(remoteSource)
        viewModel.dismissCurrentError()

        XCTAssertEqual(viewModel.activeDataSource?.id, remoteSource.id)
        XCTAssertEqual(recorder.connectedSourceIDs, [remoteSource.id])
        XCTAssertEqual(localSource.listCallCount, 0)
        XCTAssertTrue(viewModel.folders.allSatisfy { $0.dataSourceID == remoteSource.id })
        XCTAssertTrue(viewModel.files.allSatisfy { !$0.url.isFileURL })
        XCTAssertEqual(viewModel.breadcrumbSegments.first?.name, remoteSource.name)
    }

    @MainActor
    func testRetryAfterRemoteFailureRetriesSameSourceWithoutLocalFallback() async throws {
        let localSourceID = UUID()
        let localSource = SourceIsolationLocalSource(ownerDataSourceID: localSourceID)
        let recorder = RemoteInvocationRecorder()
        let remoteSource = try makeWebDAVSource(name: "AList E2E", host: "127.0.0.1")
        let viewModel = makeViewModel(localSource: localSource) { source, _ in
            SourceIsolationRemoteAdapter(
                sourceID: source.id,
                recorder: recorder,
                failure: .listing
            )
        }

        await viewModel.connectToDataSource(remoteSource)
        await viewModel.loadFiles()

        XCTAssertEqual(viewModel.activeDataSource?.id, remoteSource.id)
        XCTAssertEqual(recorder.connectedSourceIDs, [remoteSource.id, remoteSource.id])
        XCTAssertEqual(localSource.listCallCount, 0)
        XCTAssertTrue(viewModel.folders.allSatisfy { $0.dataSourceID == remoteSource.id })
        XCTAssertTrue(viewModel.files.allSatisfy { !$0.url.isFileURL })
        XCTAssertEqual(viewModel.breadcrumbSegments.first?.name, remoteSource.name)
    }

    @MainActor
    func testLateRemoteCallbackCannotOverwriteNewSourceResults() async throws {
        let localSource = SourceIsolationLocalSource(ownerDataSourceID: UUID())
        let recorder = RemoteInvocationRecorder()
        let firstSource = try makeWebDAVSource(name: "Slow Source", host: "slow.example")
        let secondSource = try makeWebDAVSource(name: "Current Source", host: "current.example")
        let viewModel = makeViewModel(localSource: localSource) { source, _ in
            SourceIsolationRemoteAdapter(
                sourceID: source.id,
                recorder: recorder,
                latency: source.id == firstSource.id ? .milliseconds(150) : nil
            )
        }

        let slowConnection = Task { await viewModel.connectToDataSource(firstSource) }
        try await Task.sleep(for: .milliseconds(30))
        await viewModel.connectToDataSource(secondSource)
        await slowConnection.value

        XCTAssertEqual(viewModel.activeDataSource?.id, secondSource.id)
        XCTAssertFalse(viewModel.folders.isEmpty)
        XCTAssertTrue(viewModel.folders.allSatisfy { $0.dataSourceID == secondSource.id })
        XCTAssertTrue(viewModel.files.allSatisfy { $0.url.host() == secondSource.id.uuidString.lowercased() })
        XCTAssertEqual(viewModel.breadcrumbSegments.first?.name, secondSource.name)
        XCTAssertEqual(localSource.listCallCount, 0)
    }

    @MainActor
    private func makeViewModel(
        localSource: SourceIsolationLocalSource,
        makeRemoteAdapter: @escaping @MainActor (
            FileBrowsingDomain.DataSource,
            any CredentialStoring
        ) -> (any DataSourceConnecting & FileProviding)?
    ) -> FileBrowsingViewModel {
        FileBrowsingViewModel(
            localDataSource: localSource,
            credentialStore: SourceIsolationCredentialStore(),
            savedDataSourceStore: SourceIsolationSavedDataSourceStore(),
            progressStore: SourceIsolationProgressStore(),
            localDataSourceID: localSource.ownerDataSourceID,
            makeRemoteAdapter: makeRemoteAdapter,
            onPlayFile: { _ in }
        )
    }

    private func makeWebDAVSource(
        name: String,
        host: String
    ) throws -> FileBrowsingDomain.DataSource {
        FileBrowsingDomain.DataSource(
            name: name,
            sourceType: .webDAV,
            connectionInfo: try .remote(sourceType: .webDAV, address: "http://\(host):5244/e2e")
        )
    }
}

private nonisolated final class SourceIsolationLocalSource: LocalFileSource, @unchecked Sendable {
    var ownerDataSourceID: UUID
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private let lock = NSLock()
    private var listCalls = 0

    var listCallCount: Int { lock.withLock { listCalls } }

    init(ownerDataSourceID: UUID) {
        self.ownerDataSourceID = ownerDataSourceID
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connected
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        lock.withLock { listCalls += 1 }
        return [
            FileBrowsingDomain.MediaFile(
                name: "private-local.mov",
                sizeInBytes: 1,
                modifiedAt: .distantPast,
                fileExtension: "mov",
                url: URL(fileURLWithPath: "/Users/test/Documents/private-local.mov")
            )
        ]
    }

    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        lock.withLock { listCalls += 1 }
        return [
            FileBrowsingDomain.MediaFolder(
                name: "Private Local Folder",
                dataSourceID: ownerDataSourceID,
                path: "/Users/test/Documents/Private Local Folder",
                url: URL(fileURLWithPath: "/Users/test/Documents/Private Local Folder", isDirectory: true)
            )
        ]
    }

    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL { item.url }

    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> FilePlaybackSource {
        FilePlaybackSource(url: file.url)
    }
}

private nonisolated final class RemoteInvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var connected: [UUID] = []

    var connectedSourceIDs: [UUID] { lock.withLock { connected } }

    func recordConnection(sourceID: UUID) {
        lock.withLock { connected.append(sourceID) }
    }
}

private nonisolated final class SourceIsolationRemoteAdapter:
    DataSourceConnecting,
    FileProviding,
    @unchecked Sendable
{
    enum Failure { case none, listing }

    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private let sourceID: UUID
    private let recorder: RemoteInvocationRecorder
    private let failure: Failure
    private let latency: Duration?

    init(
        sourceID: UUID,
        recorder: RemoteInvocationRecorder,
        failure: Failure = .none,
        latency: Duration? = nil
    ) {
        self.sourceID = sourceID
        self.recorder = recorder
        self.failure = failure
        self.latency = latency
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        recorder.recordConnection(sourceID: sourceID)
        connectionStatus = .connected
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        if let latency { try await Task.sleep(for: latency) }
        if failure == .listing { throw SourceIsolationError.remoteUnavailable }
        return [
            FileBrowsingDomain.MediaFile(
                name: "remote.mov",
                sizeInBytes: 1,
                modifiedAt: .distantPast,
                fileExtension: "mov",
                url: URL(string: "https://\(sourceID.uuidString.lowercased())/remote.mov")!
            )
        ]
    }

    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        if failure == .listing { throw SourceIsolationError.remoteUnavailable }
        return [
            FileBrowsingDomain.MediaFolder(
                name: "Remote Folder",
                dataSourceID: sourceID,
                path: "/Remote Folder",
                url: URL(string: "https://\(sourceID.uuidString.lowercased())/Remote%20Folder")!
            )
        ]
    }

    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL { item.url }

    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> FilePlaybackSource {
        FilePlaybackSource(url: file.url)
    }
}

private nonisolated enum SourceIsolationError: LocalizedError {
    case remoteUnavailable

    var errorDescription: String? { "remote unavailable" }
}

private nonisolated final class SourceIsolationCredentialStore: CredentialStoring, @unchecked Sendable {
    func saveCredential(for sourceID: String, credential: StorageCredential) throws {}
    func loadCredential(for sourceID: String) throws -> StorageCredential? { nil }
    func deleteCredential(for sourceID: String) throws {}
}

private nonisolated final class SourceIsolationSavedDataSourceStore:
    SavedDataSourceRecordStoring,
    @unchecked Sendable
{
    func loadSavedDataSourceRecords() -> Data? { nil }
    func saveSavedDataSourceRecords(_ data: Data?) {}
}

private nonisolated final class SourceIsolationProgressStore: ProgressStoring, @unchecked Sendable {
    func saveProgress(_ progress: PersistenceDomain.PlaybackProgress) async {}
    func loadProgress(
        for fileID: PersistenceDomain.FileIdentifier
    ) async -> PersistenceDomain.PlaybackProgress? { nil }
    func cleanExpiredProgress(olderThan days: Int) async {}
}
