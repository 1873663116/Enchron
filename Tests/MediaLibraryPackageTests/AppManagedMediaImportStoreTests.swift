import Foundation
import Testing
@testable import MediaLibrary

@MainActor
struct AppManagedMediaImportStoreTests {
#if DEBUG
    @Test("system import delivery snapshots bind Photos transfer bytes to persistent references")
    func photosDeliverySnapshotBindsTransferToPersistence() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let bytes = Data([0x10, 0x20, 0x30, 0x40])
        let deliveredURL = try fixture.makeProviderFile(
            directory: "Managed",
            name: "Picked Clip.mov",
            bytes: bytes
        )
        let requestID = SystemImportDeliveryDiagnostics.beginRequest(
            deliveryDomain: .appManagedPhotoTransfer
        )

        SystemImportDeliveryDiagnostics.recordPhotosTransferCompletion(
            requestID: requestID,
            assetIdentifier: "9F44CEAD-DF9B-4B05-93C0-59A245468466",
            deliveredURL: deliveredURL
        )
        let referenceID = UUID()
        SystemImportDeliveryDiagnostics.recordPersistentLibraryDelivery(
            deliveredURLs: [deliveredURL],
            newReferences: [
                .init(
                    id: referenceID,
                    name: deliveredURL.lastPathComponent,
                    locator: .file(bookmark: Data([0x01]), relativePath: ""),
                    sizeInBytes: Int64(bytes.count)
                )
            ],
            errorDescription: nil
        )

        let snapshot = try #require(SystemImportDeliveryDiagnostics.latestSnapshot)
        #expect(snapshot.schema == "enchron.regression.system-import-delivery@1")
        #expect(snapshot.requestID == requestID.uuidString.lowercased())
        #expect(snapshot.routeIdentity == "app-managed-photo-transfer:\(requestID.uuidString.lowercased())")
        #expect(snapshot.deliveryDomain == .appManagedPhotoTransfer)
        #expect(snapshot.items == [
            .init(
                returnedIdentityKind: .photosAsset,
                returnedIdentity: "9F44CEAD-DF9B-4B05-93C0-59A245468466",
                deliveredName: "Picked Clip.mov",
                byteCount: Int64(bytes.count),
                sha256: SystemImportDeliveryDiagnostics.sha256(bytes)
            )
        ])
        #expect(snapshot.persistentLibraryDelivery == .init(
            outcome: .persisted,
            references: [
                .init(
                    id: referenceID.uuidString.lowercased(),
                    name: "Picked Clip.mov",
                    locatorKind: "file",
                    sizeInBytes: Int64(bytes.count)
                )
            ],
            errorDescription: nil
        ))
    }
#endif

    @Test("a persistent library rejection is recorded with the delivered evidence")
    func persistentLibraryRejectionRecordsDeliveredEvidence() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let bytes = Data([0x70, 0x80, 0x90])
        let deliveredURL = try fixture.makeProviderFile(
            directory: "Managed",
            name: "Rejected Clip.mov",
            bytes: bytes
        )
        let requestID = SystemImportDeliveryDiagnostics.beginRequest(
            deliveryDomain: .appManagedPhotoTransfer
        )

        SystemImportDeliveryDiagnostics.recordPhotosTransferCompletion(
            requestID: requestID,
            assetIdentifier: nil,
            deliveredURL: deliveredURL
        )
        SystemImportDeliveryDiagnostics.recordPersistentLibraryDelivery(
            deliveredURLs: [deliveredURL],
            newReferences: [],
            errorDescription: nil
        )

        let snapshot = try #require(SystemImportDeliveryDiagnostics.latestSnapshot)
        #expect(snapshot.requestID == requestID.uuidString.lowercased())
        #expect(snapshot.items.map(\.deliveredName) == ["Rejected Clip.mov"])
        #expect(snapshot.persistentLibraryDelivery.outcome == .rejected)
        #expect(snapshot.persistentLibraryDelivery.errorDescription != nil)
        #expect(snapshot.persistentLibraryDelivery.references.isEmpty)
    }

    @Test("managed imports preserve bytes and the provider display filename")
    func importPreservesBytesAndDisplayFilename() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let bytes = Data([0x00, 0x11, 0x22, 0xFF])
        let provider = try fixture.makeProviderFile(
            directory: "First Provider",
            name: "Original Clip.mov",
            bytes: bytes
        )
        let store = AppManagedMediaImportStore(rootDirectory: fixture.managedRoot)

        let imported = try await store.importFile(at: provider)

        #expect(imported.lastPathComponent == "Original Clip.mov")
        #expect(try Data(contentsOf: imported) == bytes)
        #expect(try Data(contentsOf: provider) == bytes)
    }

    @Test("repeated provider names receive distinct persistent locations")
    func repeatedNamesDoNotCollideOrOverwrite() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let firstProvider = try fixture.makeProviderFile(
            directory: "First Provider",
            name: "Clip.mov",
            bytes: Data([0x01])
        )
        let secondProvider = try fixture.makeProviderFile(
            directory: "Second Provider",
            name: "Clip.mov",
            bytes: Data([0x02])
        )
        let store = AppManagedMediaImportStore(rootDirectory: fixture.managedRoot)

        let firstImport = try await store.importFile(at: firstProvider)
        let secondImport = try await store.importFile(at: secondProvider)

        #expect(firstImport != secondImport)
        #expect(firstImport.lastPathComponent == "Clip.mov")
        #expect(secondImport.lastPathComponent == "Clip.mov")
        #expect(try Data(contentsOf: firstImport) == Data([0x01]))
        #expect(try Data(contentsOf: secondImport) == Data([0x02]))
    }

    @Test("an atomic move failure removes staged and destination artifacts")
    func atomicMoveFailureCleansUp() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let provider = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Clip.mov",
            bytes: Data([0x03, 0x04])
        )
        let store = AppManagedMediaImportStore(
            rootDirectory: fixture.managedRoot,
            moveStagedFile: { _, _ in throw AtomicMoveFailure() }
        )

        do {
            _ = try await store.importFile(at: provider)
            Issue.record("The injected atomic move failure was not surfaced.")
        } catch let error as ManagedMediaImportError {
            #expect(error == .persistenceFailed(filename: "Clip.mov"))
        }

        #expect(fixture.regularFilesUnderManagedRoot().isEmpty)
        #expect(try Data(contentsOf: provider) == Data([0x03, 0x04]))
    }

    @Test("Photos imports reject playable audio before creating managed bytes")
    func admissionRequiresVideoMedia() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let provider = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Audio.mp3",
            bytes: Data([0x05])
        )
        let store = AppManagedMediaImportStore(rootDirectory: fixture.managedRoot)

        do {
            _ = try await store.importFile(at: provider)
            Issue.record("A non-video provider file was admitted.")
        } catch let error as ManagedMediaImportError {
            #expect(error == .unsupportedMedia(filename: "Audio.mp3"))
        }

        #expect(fixture.regularFilesUnderManagedRoot().isEmpty)
    }

    @Test("managed URLs enter addFiles and survive the JSON store round trip")
    func addFilesPersistsManagedReference() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let providerBytes = Data([0x06, 0x07, 0x08])
        let provider = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Library Clip.mov",
            bytes: providerBytes
        )
        let managedURL = try await AppManagedMediaImportStore(
            rootDirectory: fixture.managedRoot
        ).importFile(at: provider)
        let libraryStore = UserDefaultsMediaLibraryStore(defaults: fixture.defaults)
        let viewModel = MediaLibraryViewModel(
            store: libraryStore,
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        viewModel.addFiles([managedURL])

        let reference = try #require(viewModel.references.only)
        #expect(reference.name == "Library Clip.mov")
        #expect(try libraryStore.load() == viewModel.library)

        let reloaded = MediaLibraryViewModel(
            store: libraryStore,
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )
        #expect(reloaded.references.map(\.name) == ["Library Clip.mov"])

        viewModel.remove(reference)
        #expect(viewModel.references.isEmpty)
        #expect(try Data(contentsOf: managedURL) == providerBytes)
        #expect(try Data(contentsOf: provider) == providerBytes)
    }

    @Test("library folder removal does not delete managed or provider bytes")
    func folderRemovalDoesNotOwnImportedBytes() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let providerBytes = Data([0x0A, 0x0B])
        let provider = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Folder Clip.mov",
            bytes: providerBytes
        )
        let managedURL = try await AppManagedMediaImportStore(
            rootDirectory: fixture.managedRoot
        ).importFile(at: provider)
        let viewModel = MediaLibraryViewModel(
            store: UserDefaultsMediaLibraryStore(defaults: fixture.defaults),
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        viewModel.createFolder(named: "Photos")
        let folder = try #require(viewModel.folders.only)
        viewModel.open(folder)
        viewModel.addFiles([managedURL])
        viewModel.navigateToRoot()
        viewModel.remove(folder)

        #expect(viewModel.folders.isEmpty)
        #expect(viewModel.references.map(\.name) == ["Folder Clip.mov"])
        #expect(try Data(contentsOf: managedURL) == providerBytes)
        #expect(try Data(contentsOf: provider) == providerBytes)
    }

    @Test("unsupported media never publishes an earlier batch reference")
    func unsupportedBatchIsAtomic() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let provider = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Valid Clip.mov",
            bytes: Data([0x0C])
        )
        let managedURL = try await AppManagedMediaImportStore(
            rootDirectory: fixture.managedRoot
        ).importFile(at: provider)
        let unsupportedURL = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Unsupported.txt",
            bytes: Data([0x0D])
        )
        let viewModel = MediaLibraryViewModel(
            store: UserDefaultsMediaLibraryStore(defaults: fixture.defaults),
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        viewModel.addFiles([managedURL, unsupportedURL])

        #expect(viewModel.library == FileBrowsingDomain.MediaLibrary())
        #expect(viewModel.lastErrorMessage != nil)
        #expect(try Data(contentsOf: managedURL) == Data([0x0C]))
    }

    @Test("a JSON save failure never publishes a managed reference")
    func addFilesSaveFailureIsAtomic() async throws {
        let fixture = try ManagedImportFixture()
        defer { fixture.remove() }
        let provider = try fixture.makeProviderFile(
            directory: "Provider",
            name: "Unsaved Clip.mov",
            bytes: Data([0x09])
        )
        let managedURL = try await AppManagedMediaImportStore(
            rootDirectory: fixture.managedRoot
        ).importFile(at: provider)
        let viewModel = MediaLibraryViewModel(
            store: FailingManagedImportLibraryStore(),
            resolver: MediaReferenceResolver(),
            onPlay: { _ in }
        )

        viewModel.addFiles([managedURL])

        #expect(viewModel.library == FileBrowsingDomain.MediaLibrary())
        #expect(viewModel.lastErrorMessage != nil)
        #expect(try Data(contentsOf: managedURL) == Data([0x09]))
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}

private struct ManagedImportFixture {
    let container: URL
    let managedRoot: URL
    let defaults: UserDefaults
    private let suiteName: String
    private let fileManager = FileManager.default

    init() throws {
        container = FileManager.default.temporaryDirectory.appending(
            path: "enchron-managed-import-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        managedRoot = container.appending(
            path: "Application Support/Managed Media",
            directoryHint: .isDirectory
        )
        suiteName = "app.enchron.tests.managed-import.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
    }

    func makeProviderFile(
        directory: String,
        name: String,
        bytes: Data
    ) throws -> URL {
        let providerDirectory = container.appending(
            path: directory,
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: providerDirectory,
            withIntermediateDirectories: true
        )
        let url = providerDirectory.appending(path: name)
        try bytes.write(to: url)
        return url
    }

    func regularFilesUnderManagedRoot() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: managedRoot,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            files.append(url)
        }
        return files
    }

    func remove() {
        try? fileManager.removeItem(at: container)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct AtomicMoveFailure: Error {}

private struct FailingManagedImportLibraryStore: MediaLibraryStoring {
    struct SaveFailure: Error {}

    func load() throws -> FileBrowsingDomain.MediaLibrary {
        FileBrowsingDomain.MediaLibrary()
    }

    func save(_: FileBrowsingDomain.MediaLibrary) throws {
        throw SaveFailure()
    }
}
