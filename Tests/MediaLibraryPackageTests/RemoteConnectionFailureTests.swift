import Foundation
import MediaSource
@testable import MediaLibrary
import Testing

struct RemoteConnectionFailureTests {
    @Test("connection results expose one success and exactly four typed failures")
    func finiteResultDomain() {
        #expect(
            RemoteConnectionFailure.allCases == [
                .credentialsRejected,
                .serverUnreachable,
                .invalidAddress,
                .requiresHTTPS
            ]
        )

        let results = [RemoteConnectionResult.connected]
            + RemoteConnectionFailure.allCases.map(RemoteConnectionResult.failed)

        #expect(results.count == 5)
    }

    @Test("URL connection failures retain their causal domain classification")
    func urlFailureClassification() async throws {
        let diagnoser = RemoteConnectionFailureDiagnoser { _ in
            Issue.record("HTTPS URLs must not trigger the plaintext TLS probe")
            return false
        }
        let attemptedURL = try #require(URL(string: "https://media.example.test"))

        let credentials = await diagnoser.diagnose(
            URLError(.userAuthenticationRequired),
            attemptedURL: attemptedURL
        )
        let unreachable = await diagnoser.diagnose(
            URLError(.timedOut),
            attemptedURL: attemptedURL
        )
        let invalidAddress = await diagnoser.diagnose(
            URLError(.badURL),
            attemptedURL: attemptedURL
        )

        #expect(credentials == .credentialsRejected)
        #expect(unreachable == .serverUnreachable)
        #expect(invalidAddress == .invalidAddress)
    }

    @MainActor
    @Test("MediaLibrary maps adapter errors without inspecting presentation copy")
    func adapterFailureMapping() {
        #expect(
            FileBrowsingViewModel.connectionFailure(for: SMBError.authenticationFailed)
                == .credentialsRejected
        )
        #expect(
            FileBrowsingViewModel.connectionFailure(for: SMBError.invalidConnectionInfo)
                == .invalidAddress
        )
        #expect(
            FileBrowsingViewModel.connectionFailure(for: SMBError.networkFailed("offline"))
                == .serverUnreachable
        )
        #expect(
            FileBrowsingViewModel.connectionFailure(for: WebDAVError.requestFailed(403))
                == .credentialsRejected
        )
        #expect(
            FileBrowsingViewModel.connectionFailure(for: URLError(.cannotFindHost))
                == .serverUnreachable
        )
    }

    @MainActor
    @Test("FileBrowsingViewModel returns the typed result without a message side channel")
    func viewModelReturnsTypedResult() async {
        let failureAdapter = ConnectionResultAdapter(failure: .credentialsRejected)
        let failureViewModel = makeViewModel(adapter: failureAdapter)
        let source = makeRemoteSource()

        let failureResult = await failureViewModel.connectToDataSource(source)

        #expect(failureResult == .failed(.credentialsRejected))
        #expect(failureViewModel.lastErrorMessage == nil)

        let successAdapter = ConnectionResultAdapter(failure: nil)
        let successViewModel = makeViewModel(adapter: successAdapter)

        let successResult = await successViewModel.connectToDataSource(source)

        #expect(successResult == .connected)
        #expect(successViewModel.lastErrorMessage == nil)
    }

    @MainActor
    @Test("automatic WebDAV and SMB reconnect failures remain visible through retry")
    func automaticReconnectFailuresRemainVisible() async {
        await expectAutomaticReconnectFailure(for: .webDAV)
        await expectAutomaticReconnectFailure(for: .smb)
    }

    @MainActor
    private func expectAutomaticReconnectFailure(
        for sourceType: FileBrowsingDomain.SourceType
    ) async {
        let adapter = AutomaticReconnectFailureAdapter(sourceType: sourceType)
        let viewModel = makeViewModel(adapter: adapter)
        let source = makeRemoteSource(sourceType: sourceType)

        #expect(await viewModel.connectToDataSource(source) == .connected)

        await viewModel.loadFiles()

        #expect(adapter.connectCallCount == 2)
        #expect(
            viewModel.lastErrorMessage
                == RemoteConnectionFailure.credentialsRejected.sourceConnectionMessage
        )

        viewModel.dismissCurrentError()
        await viewModel.loadFiles()

        #expect(adapter.connectCallCount == 3)
        #expect(
            viewModel.lastErrorMessage
                == RemoteConnectionFailure.credentialsRejected.sourceConnectionMessage
        )
    }

    @MainActor
    private func makeViewModel(
        adapter: any DataSourceConnecting & FileProviding
    ) -> FileBrowsingViewModel {
        FileBrowsingViewModel(
            localDataSource: FakeFileDataSource(),
            credentialStore: EmptyCredentialStore(),
            savedDataSourceStore: EmptySavedDataSourceStore(),
            makeRemoteAdapter: { _, _ in adapter },
            onPlayFile: { _ in }
        )
    }

    private func makeRemoteSource(
        sourceType: FileBrowsingDomain.SourceType = .webDAV
    ) -> FileBrowsingDomain.DataSource {
        let scheme = sourceType == .smb ? "smb" : "https"
        return FileBrowsingDomain.DataSource(
            name: "Test \(sourceType.title)",
            sourceType: sourceType,
            connectionInfo: FileBrowsingDomain.ConnectionInfo(
                sourceType: sourceType,
                address: "\(scheme)://media.example.test",
                scheme: scheme,
                host: "media.example.test"
            )
        )
    }
}

private nonisolated final class AutomaticReconnectFailureAdapter:
    DataSourceConnecting,
    FileProviding,
    @unchecked Sendable {
    private let sourceType: FileBrowsingDomain.SourceType
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private(set) var connectCallCount = 0
    private var contentListCallCount = 0

    init(sourceType: FileBrowsingDomain.SourceType) {
        self.sourceType = sourceType
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectCallCount += 1
        guard connectCallCount == 1 else {
            connectionStatus = .failed(.credentialsRejected)
            throw RemoteConnectionFailure.credentialsRejected
        }
        connectionStatus = .connected
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        contentListCallCount += 1
        guard contentListCallCount == 1 else {
            switch sourceType {
            case .smb:
                throw SMBError.notConnected
            case .webDAV:
                throw WebDAVError.notConnected
            case .local:
                Issue.record("automatic remote reconnect cannot use a local source")
                return []
            }
        }
        return []
    }

    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] { [] }
    func listSubtitleFiles(at path: String) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL { item.url }

    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> ResolvedMediaSource {
        ResolvedMediaSource(url: file.url)
    }
}

private nonisolated final class ConnectionResultAdapter:
    DataSourceConnecting,
    FileProviding,
    @unchecked Sendable {
    private let failure: RemoteConnectionFailure?
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

    init(failure: RemoteConnectionFailure?) {
        self.failure = failure
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        if let failure {
            connectionStatus = .failed(failure)
            throw failure
        }
        connectionStatus = .connected
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] { [] }
    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] { [] }
    func listSubtitleFiles(at path: String) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] { [] }

    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL { item.url }

    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> ResolvedMediaSource {
        ResolvedMediaSource(url: file.url)
    }
}

private nonisolated struct EmptyCredentialStore: CredentialStoring {
    func saveCredential(for sourceID: String, credential: StorageCredential) throws {}
    func loadCredential(for sourceID: String) throws -> StorageCredential? { nil }
    func deleteCredential(for sourceID: String) throws {}
}

private nonisolated struct EmptySavedDataSourceStore: SavedDataSourceRecordStoring {
    func loadSavedDataSourceRecords() -> Data? { nil }
    func saveSavedDataSourceRecords(_ data: Data?) {}
}
