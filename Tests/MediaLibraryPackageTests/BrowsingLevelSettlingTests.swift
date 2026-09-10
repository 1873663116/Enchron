import Foundation
import MediaSource
@testable import MediaLibrary
import Testing

struct BrowsingLevelSettlingTests {
    @MainActor
    @Test("a connected source root has settled and carries its listing")
    func rootSettlesOnConnection() async {
        let gate = ListingGate(isOpen: true)
        let viewModel = makeViewModel(adapter: GatedListingAdapter(gate: gate))
        let source = makeRemoteSource()

        #expect(await viewModel.connectToDataSource(source) == .connected)
        #expect(viewModel.currentLevelHasSettled)
        #expect(viewModel.files.isEmpty == false)
    }

    @MainActor
    @Test("entering a level drops the level being left until the new listing lands")
    func enteringALevelDropsThePreviousListing() async {
        let gate = ListingGate(isOpen: true)
        let adapter = GatedListingAdapter(gate: gate)
        let viewModel = makeViewModel(adapter: adapter)

        #expect(await viewModel.connectToDataSource(makeRemoteSource()) == .connected)
        let leftBehind = viewModel.files
        #expect(leftBehind.isEmpty == false)

        await gate.close()
        let navigation = Task { await viewModel.navigateToFolder(makeFolder(path: "/child")) }
        await gate.waitForEntry()

        #expect(viewModel.currentLevelHasSettled == false)
        #expect(viewModel.files.isEmpty)
        #expect(viewModel.folders.isEmpty)

        await gate.open()
        await navigation.value

        #expect(viewModel.currentLevelHasSettled)
        #expect(viewModel.files.map(\.name) == ["/child.mkv"])
    }

    @MainActor
    @Test("a listing that fails still settles the level it was entering")
    func aFailedListingSettlesTheLevel() async {
        let adapter = GatedListingAdapter(
            gate: ListingGate(isOpen: true),
            failingPaths: ["/child"]
        )
        let viewModel = makeViewModel(adapter: adapter)

        #expect(await viewModel.connectToDataSource(makeRemoteSource()) == .connected)
        await viewModel.navigateToFolder(makeFolder(path: "/child"))

        #expect(viewModel.currentLevelHasSettled)
        #expect(viewModel.lastErrorMessage != nil)
        #expect(viewModel.files.isEmpty)
    }

    @MainActor
    @Test("refreshing a level in place leaves it settled")
    func refreshingDoesNotReopenTheLevel() async {
        let viewModel = makeViewModel(adapter: GatedListingAdapter(gate: ListingGate(isOpen: true)))

        #expect(await viewModel.connectToDataSource(makeRemoteSource()) == .connected)
        await viewModel.loadFiles()

        #expect(viewModel.currentLevelHasSettled)
        #expect(viewModel.files.isEmpty == false)
    }

    @MainActor
    @Test("leaving a level upward drops its listing until the parent's lands")
    func leavingALevelDropsItsListing() async {
        let gate = ListingGate(isOpen: true)
        let viewModel = makeViewModel(adapter: GatedListingAdapter(gate: gate))

        #expect(await viewModel.connectToDataSource(makeRemoteSource()) == .connected)
        await viewModel.navigateToFolder(makeFolder(path: "/child"))
        #expect(viewModel.files.map(\.name) == ["/child.mkv"])

        await gate.close()
        let navigation = Task { await viewModel.navigateUp() }
        await gate.waitForEntry()

        #expect(viewModel.currentLevelHasSettled == false)
        #expect(viewModel.files.isEmpty)

        await gate.open()
        await navigation.value

        #expect(viewModel.currentLevelHasSettled)
        #expect(viewModel.files.isEmpty == false)
    }

    @MainActor
    private func makeViewModel(
        adapter: any DataSourceConnecting & FileProviding
    ) -> FileBrowsingViewModel {
        FileBrowsingViewModel(
            localDataSource: FakeFileDataSource(),
            credentialStore: LevelTestCredentialStore(),
            savedDataSourceStore: LevelTestSavedDataSourceStore(),
            makeRemoteAdapter: { _, _ in adapter },
            onPlayFile: { _ in }
        )
    }

    private func makeRemoteSource() -> FileBrowsingDomain.DataSource {
        FileBrowsingDomain.DataSource(
            name: "Test WebDAV",
            sourceType: .webDAV,
            connectionInfo: FileBrowsingDomain.ConnectionInfo(
                sourceType: .webDAV,
                address: "https://media.example.test",
                scheme: "https",
                host: "media.example.test"
            )
        )
    }

    private func makeFolder(path: String) -> FileBrowsingDomain.MediaFolder {
        FileBrowsingDomain.MediaFolder(
            name: (path as NSString).lastPathComponent,
            dataSourceID: UUID(),
            path: path,
            url: URL(fileURLWithPath: path)
        )
    }
}

private actor ListingGate {
    private var isOpen: Bool
    private var hasEntered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    init(isOpen: Bool) {
        self.isOpen = isOpen
    }

    func enter() async {
        hasEntered = true
        let waiting = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiting { waiter.resume() }
        guard isOpen == false else { return }
        await withCheckedContinuation { openWaiters.append($0) }
    }

    func waitForEntry() async {
        guard hasEntered == false else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = openWaiters
        openWaiters.removeAll()
        for waiter in waiting { waiter.resume() }
    }

    func close() {
        isOpen = false
        hasEntered = false
    }
}

private nonisolated final class GatedListingAdapter:
    DataSourceConnecting,
    FileProviding,
    @unchecked Sendable {
    private let gate: ListingGate
    private let failingPaths: Set<String>
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

    init(gate: ListingGate, failingPaths: Set<String> = []) {
        self.gate = gate
        self.failingPaths = failingPaths
    }

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connected
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        await gate.enter()
        if failingPaths.contains(path) {
            throw WebDAVError.requestFailed(404)
        }
        return [
            FileBrowsingDomain.MediaFile(
                name: "\(path).mkv",
                sizeInBytes: 1,
                modifiedAt: Date(timeIntervalSince1970: 0),
                fileExtension: "mkv",
                url: URL(fileURLWithPath: "\(path)/one.mkv")
            )
        ]
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

private nonisolated struct LevelTestCredentialStore: CredentialStoring {
    func saveCredential(for sourceID: String, credential: StorageCredential) throws {}
    func loadCredential(for sourceID: String) throws -> StorageCredential? { nil }
    func deleteCredential(for sourceID: String) throws {}
}

private nonisolated struct LevelTestSavedDataSourceStore: SavedDataSourceRecordStoring {
    func loadSavedDataSourceRecords() -> Data? { nil }
    func saveSavedDataSourceRecords(_ data: Data?) {}
}
