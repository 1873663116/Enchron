import Foundation
import MediaSource
import Observation
import OSLog

@MainActor
@Observable
public final class FileBrowsingViewModel {
    public var files: [FileBrowsingDomain.MediaFile] = []
    public var folders: [FileBrowsingDomain.MediaFolder] = []
    public var isLoading: Bool = false
    public var lastErrorMessage: String?
    public var sortCriteria: FileBrowsingDomain.SortCriteria = .nameAscending {
        didSet { applySortToFiles() }
    }
    public private(set) var currentRootDisplayName: String = "Documents"
    public private(set) var currentRemotePath: String = "/"
    public private(set) var canNavigateUp: Bool = false

    public var savedDataSources: [FileBrowsingDomain.DataSource] = []
    public var activeDataSource: FileBrowsingDomain.DataSource?

    /// Set by the app layer when navigating to the detail page for a file.
    /// The detail view reads this to know which file is being inspected.
    public var detailNavigationRequest: MediaPlaybackItem?

    /// Last-known viewing state loaded in one folder-entry background pass.
    public private(set) var fileViewingStates: [UUID: VideoCardViewingState] = [:]

    /// Live search query (UC-FILE-33). Filters the displayed file/folder lists by
    /// name; the underlying `files`/`folders` arrays are untouched, so clearing the
    /// query restores the full listing.
    public var searchText: String = ""

    /// Files after applying the live search filter (UC-FILE-33).
    public var displayedFiles: [FileBrowsingDomain.MediaFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Folders after applying the live search filter (UC-FILE-33).
    public var displayedFolders: [FileBrowsingDomain.MediaFolder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return folders }
        return folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// True when a level popped by `navigateUp` can be redone via `navigateForward` (UC-FILE-37).
    public private(set) var canNavigateForward: Bool = false

    private let localDataSource: any LocalFileSource
    private let logger = Logger(subsystem: "app.enchron", category: "FileBrowser")
    private let fileManager: FileManager
    private let credentialStoreForConfig: CredentialStoring
    private let savedDataSourceStore: SavedDataSourceRecordStoring
    private let viewingStateProvider: MediaViewingStateProvider
    private var credentialStore: CredentialStoring { credentialStoreForConfig }
    private let onPlayFile: @MainActor (MediaPlaybackItem) -> Void
    private let onPrepareFile: (@MainActor (MediaPlaybackItem) -> Void)?
    private let defaultRootURL: URL
    public let localDataSourceID: UUID
    private var rootURL: URL
    private var securityScopedRootURL: URL?
    private var activeRemoteAdapter: (any DataSourceConnecting & FileProviding)?
    private var remotePathStack: [String] = []
    /// Levels popped by `navigateUp`, available to redo via `navigateForward` (UC-FILE-37).
    private var forwardPathStack: [String] = []
    private var reconnectAttempted: Bool = false
    private var sourceGeneration: UInt64 = 0
    private var playbackCollection: [FileBrowsingDomain.MediaFile] = []
    private var currentPlaybackFileID: UUID?

    /// Injectable remote-adapter factory (FILE-10 / 44 / 46 testability). It receives
    /// the credential view used for this connection, including any uncommitted overlay. When nil,
    /// `connectToDataSource` builds the real WebDAV / SMB / Photo adapters; tests
    /// inject a fake that times out / rejects credentials / succeeds deterministically.
    /// Returns nil to fall through to the built-in adapters (e.g. for `.local`).
    private let makeRemoteAdapter: (@MainActor (
        FileBrowsingDomain.DataSource,
        any CredentialStoring
    ) -> (any DataSourceConnecting & FileProviding)?)?

    init(
        localDataSource: any LocalFileSource,
        fileManager: FileManager = .default,
        credentialStore: CredentialStoring = KeychainStore(),
        savedDataSourceStore: SavedDataSourceRecordStoring = SavedDataSourceStore(),
        viewingStateProvider: @escaping MediaViewingStateProvider = { _ in nil },
        localDataSourceID: UUID = UUID(),
        makeRemoteAdapter: (@MainActor (
            FileBrowsingDomain.DataSource,
            any CredentialStoring
        ) -> (any DataSourceConnecting & FileProviding)?)? = nil,
        onPlayFile: @escaping @MainActor (MediaPlaybackItem) -> Void,
        onPrepareFile: (@MainActor (MediaPlaybackItem) -> Void)? = nil
    ) {
        self.localDataSource = localDataSource
        self.fileManager = fileManager
        self.credentialStoreForConfig = credentialStore
        self.savedDataSourceStore = savedDataSourceStore
        self.viewingStateProvider = viewingStateProvider
        self.localDataSourceID = localDataSourceID
        self.makeRemoteAdapter = makeRemoteAdapter
        self.onPlayFile = onPlayFile
        self.onPrepareFile = onPrepareFile
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.defaultRootURL = documentsURL
        self.rootURL = documentsURL
        self.currentRootDisplayName = documentsURL.lastPathComponent.isEmpty ? documentsURL.path : documentsURL.lastPathComponent
        self.localDataSource.ownerDataSourceID = localDataSourceID

        loadSavedDataSources()
    }

    public func saveCredential(
        for dataSource: FileBrowsingDomain.DataSource,
        username: String,
        password: String
    ) throws {
        try credentialStore.saveCredential(
            for: dataSource.credentialSourceID,
            credential: StorageCredential(username: username, password: password)
        )
    }

    public func deleteCredential(for dataSource: FileBrowsingDomain.DataSource) {
        do {
            try credentialStore.deleteCredential(for: dataSource.credentialSourceID)
        } catch {
            print("[FileBrowser] Failed to delete credential for \(dataSource.credentialSourceID): \(error)")
        }
    }

    public func dismissCurrentError() {
        lastErrorMessage = nil
    }

    public func addDataSource(_ ds: FileBrowsingDomain.DataSource) {
        if !savedDataSources.contains(where: { $0.id == ds.id }) {
            savedDataSources.append(ds)
        }
        persistDataSources()
    }

    public func removeDataSource(id: UUID) {
        guard let removedSource = savedDataSources.first(where: { $0.id == id }) else {
            return
        }
        savedDataSources.removeAll { $0.id == id }
        if savedDataSources.contains(where: {
            $0.credentialSourceID == removedSource.credentialSourceID
        }) == false {
            deleteCredential(for: removedSource)
        }
        persistDataSources()

        if activeDataSource?.id == id {
            Task { [weak self] in
                await self?.useDefaultFolder()
            }
        }
    }

    public func loadSavedDataSources() {
        guard let data = savedDataSourceStore.loadSavedDataSourceRecords(),
              let records = try? JSONDecoder().decode([SavedDataSourceRecord].self, from: data)
        else {
            return
        }
        savedDataSources = records.compactMap(\.domainValue)
    }

    public func connectToDataSource(
        _ ds: FileBrowsingDomain.DataSource,
        credential: StorageCredential? = nil
    ) async {
        let generation = beginSourceGeneration()
        // Immediately update UI state so the caller sees a skeleton screen
        // rather than stale content from the previous data source.
        activeDataSource = ds
        isLoading = true
        files = []
        folders = []
        currentRootDisplayName = ds.name
        let rootPath = ds.connectionInfo.rootPath
        remotePathStack = [rootPath]
        forwardPathStack = []
        currentRemotePath = rootPath
        canNavigateUp = false
        canNavigateForward = false

        let adapterCredentialStore: any CredentialStoring
        if let credential {
            adapterCredentialStore = CredentialOverlayStore(
                base: credentialStore,
                sourceID: ds.credentialSourceID,
                credential: credential
            )
        } else {
            adapterCredentialStore = credentialStore
        }

        let adapter: any DataSourceConnecting & FileProviding
        // FILE-10/44/46: an injected factory overrides the real adapters (e.g. a
        // fake that times out / rejects / succeeds). Returning nil falls through.
        if let injected = makeRemoteAdapter?(ds, adapterCredentialStore) {
            adapter = injected
        } else {
            switch ds.connectionInfo.sourceType {
            case .webDAV:
                let webDAV = WebDAVDataSourceAdapter(credentialStore: adapterCredentialStore)
                webDAV.ownerDataSourceID = ds.id
                adapter = webDAV
            case .smb:
                let smb = SMBDataSourceAdapter(credentialStore: adapterCredentialStore)
                smb.ownerDataSourceID = ds.id
                adapter = smb
            case .local:
                await useDefaultFolder()
                return
            case .photoLibrary:
                isLoading = false
                lastErrorMessage = "Choose Photos videos from the Media Library add menu."
                return
            }
        }

        activeRemoteAdapter?.disconnect()
        do {
            try await adapter.connect(with: ds.connectionInfo)
            guard isCurrentSource(generation, dataSourceID: ds.id) else {
                adapter.disconnect()
                return
            }
            activeRemoteAdapter = adapter

            let remoteFiles = try await adapter.listContents(at: rootPath)
            let remoteFolders = try await adapter.listFolders(at: rootPath)
            guard isCurrentSource(generation, dataSourceID: ds.id) else {
                adapter.disconnect()
                return
            }
            files = remoteFiles
            folders = remoteFolders
            currentRootDisplayName = ds.name
            lastErrorMessage = nil
            isLoading = false
        } catch {
            adapter.disconnect()
            guard isCurrentSource(generation, dataSourceID: ds.id) else { return }
            isLoading = false
            activeRemoteAdapter = nil
            lastErrorMessage = Self.friendlyErrorMessage(for: error)
        }
    }

    private static func friendlyErrorMessage(for error: Error) -> String {
        if let webDAVError = error as? WebDAVError {
            switch webDAVError {
            case .requestFailed(let code) where code == 401 || code == 403:
                return "Authentication failed. Please check your username and password."
            case .requestFailed(let code):
                return "Server returned error (HTTP \(code))."
            case .invalidConnectionInfo:
                return "Invalid server address or connection settings."
            default:
                return "Connection failed: \(error.localizedDescription)"
            }
        }
        if error is SMBError {
            return error.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return "Connection timed out. Please check the server address and network."
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
                return "Cannot reach server. Please check the address and your network connection."
            default:
                return "Network error: \(error.localizedDescription)"
            }
        }
        return "Connection failed: \(error.localizedDescription)"
    }

    public func loadFiles() async {
        let generation = sourceGeneration
        isLoading = true
        defer {
            if sourceGeneration == generation {
                isLoading = false
            }
        }

        if let remoteAdapter = activeRemoteAdapter {
            let dataSourceID = activeDataSource?.id
            do {
                let newFiles = try await remoteAdapter.listContents(at: currentRemotePath)
                let newFolders = try await remoteAdapter.listFolders(at: currentRemotePath)
                guard sourceGeneration == generation,
                      activeDataSource?.id == dataSourceID else { return }
                // §5.7c: Incremental update — replace with new data only on success,
                // preserving stable UUIDs so SwiftUI diffs without rebuilding the whole list.
                mergeFiles(newFiles)
                mergeFolders(newFolders)
                lastErrorMessage = nil
            } catch {
                guard sourceGeneration == generation,
                      activeDataSource?.id == dataSourceID else { return }
                if !reconnectAttempted,
                   Self.isNetworkRecoverableError(error),
                   let ds = activeDataSource {
                    reconnectAttempted = true
                    await connectToDataSource(ds)
                    reconnectAttempted = false
                    return
                }
                // §5.7c: On failure, keep existing files/folders visible so the list
                // does not jump to empty. Only surface the error message.
                lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
            }
            applySortToFiles()
            loadProgressForFiles()
            // §5.6: Warm metadata cache for all video files in this remote folder.
            return
        }

        if let dataSource = activeDataSource {
            await connectToDataSource(dataSource)
            return
        }

        let localPath = remotePathStack.isEmpty ? "." : currentRemotePath
        do {
            let newFiles = try await localDataSource.listContents(at: localPath)
            let newFolders = try await localDataSource.listFolders(at: localPath)
            guard sourceGeneration == generation, activeDataSource == nil else { return }
            // §5.7c: Same incremental merge for local data source.
            mergeFiles(newFiles)
            mergeFolders(newFolders)
            lastErrorMessage = nil
        } catch {
            guard sourceGeneration == generation, activeDataSource == nil else { return }
            // §5.7c: On failure, preserve current list and surface the error.
            lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
            print("[FileBrowser] loadFiles failed: \(error)")
        }
        applySortToFiles()
        loadProgressForFiles()
        // §5.6: Warm metadata cache for all video files in this local folder.
    }

    /// §5.7c: Diff-update the files array in-place.
    /// - Removes entries no longer present in the new list.
    /// - Appends new entries not already in the current list.
    /// - Updates metadata (name, size, modifiedAt) for existing entries by UUID.
    /// Preserves the UUID identity SwiftUI relies on for stable diffing.
    private func mergeFiles(_ newFiles: [FileBrowsingDomain.MediaFile]) {
        // Use uniquingKeysWith to avoid a crash when the data source returns duplicate IDs.
        let newByID = Dictionary(newFiles.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let oldIDs = Set(files.map(\.id))
        let newIDs = Set(newFiles.map(\.id))

        // Remove stale entries
        files.removeAll { !newIDs.contains($0.id) }

        // Update existing entries in-place (metadata may have changed)
        files = files.map { oldFile in
            newByID[oldFile.id] ?? oldFile
        }

        // Append brand-new entries
        for file in newFiles where !oldIDs.contains(file.id) {
            files.append(file)
        }
    }

    /// §5.7c: Diff-update the folders array in-place using the same strategy.
    private func mergeFolders(_ newFolders: [FileBrowsingDomain.MediaFolder]) {
        // Use uniquingKeysWith to avoid a crash when the data source returns duplicate IDs.
        let newByID = Dictionary(newFolders.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let oldIDs = Set(folders.map(\.id))
        let newIDs = Set(newFolders.map(\.id))

        folders.removeAll { !newIDs.contains($0.id) }
        folders = folders.map { oldFolder in
            newByID[oldFolder.id] ?? oldFolder
        }
        for folder in newFolders where !oldIDs.contains(folder.id) {
            folders.append(folder)
        }
    }

    public var isInDocumentsFolder: Bool {
        rootURL.standardizedFileURL == defaultRootURL.standardizedFileURL
    }

    public func deleteFile(_ file: FileBrowsingDomain.MediaFile) async {
        guard activeRemoteAdapter == nil else {
            lastErrorMessage = "Only local files can be deleted."
            return
        }
        guard isInDocumentsFolder else {
            lastErrorMessage = "Only files in the app Documents folder can be deleted."
            return
        }
        do {
            try fileManager.removeItem(at: file.url)
            files.removeAll { $0.id == file.id }
        } catch {
            lastErrorMessage = "Failed to delete \"\(file.name)\": \(error.localizedDescription)"
        }
    }

    public func selectFile(_ file: FileBrowsingDomain.MediaFile) {
        playbackCollection = Self.naturalPlaybackCollection(from: files)
        currentPlaybackFileID = file.id
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(20))
            do {
                let request = try await playbackItem(for: file)
                logger.info("file selected name=\(file.name, privacy: .public)")
                if let onPrepareFile {
                    self.detailNavigationRequest = request
                    onPrepareFile(request)
                } else {
                    onPlayFile(request)
                }
            } catch {
                lastErrorMessage = "Failed to open \"\(file.name)\": \(error.localizedDescription)"
                logger.error("file selection failed name=\(file.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                return
            }
        }
    }

    public func playbackItem(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> MediaPlaybackItem {
        let resolvedSource: ResolvedMediaSource
        if let activeRemoteAdapter {
            resolvedSource = try await activeRemoteAdapter.resolvePlayableSource(for: file)
        } else {
            resolvedSource = try await localDataSource.resolvePlayableSource(for: file)
        }

        let playableURL = resolvedSource.url
        let stableIdentifier = makeStableIdentifier(for: file, playableURL: playableURL)
        let sourceAccess = resolvedSource.accessLease ?? (playableURL.isFileURL
            ? MediaAccessLease.securityScoped(securityScopedRootURL ?? playableURL)
            : nil)
        let versionedIdentity: VersionedMediaIdentity?
        if let dataSource = activeDataSource {
            versionedIdentity = VersionedMediaIdentity.remote(
                sourceKey: dataSource.connectionInfo.mediaIdentitySourceKey,
                canonicalPath: file.url.path,
                entityTag: file.remoteEntityTag,
                sizeInBytes: file.sizeInBytes,
                modifiedAt: file.modifiedAt
            )
        } else if activeDataSource == nil {
            versionedIdentity = VersionedMediaIdentity.local(playableURL)
        } else {
            versionedIdentity = nil
        }
        return MediaPlaybackItem(
            id: file.id,
            url: playableURL,
            displayName: file.name,
            stableIdentifier: stableIdentifier,
            sizeInBytes: file.sizeInBytes,
            collectionOrigin: .sourceDirectory,
            versionedIdentity: versionedIdentity,
            accessLease: sourceAccess
        )
    }

    public func nextPlaybackItem() async -> MediaPlaybackItem? {
        guard let currentPlaybackFileID,
              let index = playbackCollection.firstIndex(where: { $0.id == currentPlaybackFileID }),
              playbackCollection.indices.contains(index + 1) else { return nil }
        let next = playbackCollection[index + 1]
        do {
            let request = try await playbackItem(for: next)
            self.currentPlaybackFileID = next.id
            return request
        } catch {
            lastErrorMessage = "Failed to open \"\(next.name)\": \(error.localizedDescription)"
            return nil
        }
    }

    public var mediaCollectionSnapshot: MediaCollectionSnapshot {
        MediaCollectionSnapshot(entries: playbackCollection.map {
            MediaCollectionEntry(
                id: $0.id,
                displayName: $0.name,
                isCurrent: $0.id == currentPlaybackFileID
            )
        })
    }

    public func playbackItem(forCollectionItemID id: UUID) async -> MediaPlaybackItem? {
        guard let file = playbackCollection.first(where: { $0.id == id }) else { return nil }
        do {
            let request = try await playbackItem(for: file)
            currentPlaybackFileID = file.id
            return request
        } catch {
            lastErrorMessage = "Failed to open \"\(file.name)\": \(error.localizedDescription)"
            return nil
        }
    }

    private static func naturalPlaybackCollection(
        from files: [FileBrowsingDomain.MediaFile]
    ) -> [FileBrowsingDomain.MediaFile] {
        files.sorted {
            NaturalMediaNameOrder.lessThan($0.name, id: $0.id, $1.name, id: $1.id)
        }
    }

    public func resolveSourceItem(
        dataSourceID: UUID,
        path: String,
        reference: FileBrowsingDomain.MediaReference
    ) async throws -> ResolvedMediaSource {
        if dataSourceID == localDataSourceID {
            guard let url = URL(string: path) else { throw LocalDataSourceError.itemNotReachable }
            return ResolvedMediaSource(url: url)
        }
        guard let dataSource = savedDataSources.first(where: { $0.id == dataSourceID }) else {
            throw MediaReferenceResolver.ResolutionError.unavailableSource
        }

        let adapter: any DataSourceConnecting & FileProviding
        switch dataSource.sourceType {
        case .webDAV:
            let webDAV = WebDAVDataSourceAdapter(credentialStore: credentialStore)
            webDAV.ownerDataSourceID = dataSource.id
            adapter = webDAV
        case .smb:
            let smb = SMBDataSourceAdapter(credentialStore: credentialStore)
            smb.ownerDataSourceID = dataSource.id
            adapter = smb
        case .photoLibrary, .local:
            throw MediaReferenceResolver.ResolutionError.unavailableSource
        }

        do {
            try await adapter.connect(with: dataSource.connectionInfo)
            guard let url = URL(string: path) else {
                throw MediaReferenceResolver.ResolutionError.unavailableSource
            }
            let file = FileBrowsingDomain.MediaFile(
                name: reference.name,
                sizeInBytes: reference.sizeInBytes,
                modifiedAt: reference.modifiedAt,
                fileExtension: reference.fileExtension,
                url: url
            )
            let source = try await adapter.resolvePlayableSource(for: file)
            adapter.disconnect()
            return source
        } catch {
            adapter.disconnect()
            throw error
        }
    }

    public func navigateToFolder(_ folder: FileBrowsingDomain.MediaFolder) async {
        if remotePathStack.isEmpty {
            // First navigation: push the root as the stack's base entry. The stack
            // holds logical query keys, not display paths — so the local base must
            // be the same logical root the loader uses on the initial (empty-stack)
            // listing, not the filesystem `rootURL.path`. Seeding the absolute path
            // here made `navigateUp`/`navigateForward`/breadcrumb-to-root query a key
            // the source doesn't recognize, returning an empty root.
            remotePathStack.append(activeRemoteAdapter != nil ? currentRemotePath : "/")
        }
        remotePathStack.append(folder.path)
        currentRemotePath = folder.path
        canNavigateUp = remotePathStack.count > 1
        // Descending into a folder starts a new branch — the forward history is gone.
        forwardPathStack.removeAll()
        canNavigateForward = false
        currentRootDisplayName = folder.name
        await loadFiles()
    }

    public func navigateUp() async {
        guard remotePathStack.count > 1 else { return }
        let leftLevel = remotePathStack.removeLast()
        // Remember the level we left so `navigateForward` can redo it (UC-FILE-37).
        forwardPathStack.append(leftLevel)
        canNavigateForward = true
        let previousPath = remotePathStack.last ?? "/"
        currentRemotePath = previousPath
        canNavigateUp = remotePathStack.count > 1

        if let ds = activeDataSource, remotePathStack.count == 1 {
            currentRootDisplayName = ds.name
        } else if activeRemoteAdapter == nil, remotePathStack.count == 1 {
            let name = rootURL.lastPathComponent
            currentRootDisplayName = name.isEmpty ? rootURL.path : name
        } else {
            let name = (previousPath as NSString).lastPathComponent
            currentRootDisplayName = name.removingPercentEncoding ?? name
        }
        await loadFiles()
    }

    /// Redo the most recently popped level (UC-FILE-37). No-op at the head of history.
    public func navigateForward() async {
        guard let next = forwardPathStack.popLast() else { return }
        remotePathStack.append(next)
        currentRemotePath = next
        canNavigateUp = remotePathStack.count > 1
        canNavigateForward = !forwardPathStack.isEmpty
        let name = (next as NSString).lastPathComponent
        currentRootDisplayName = name.removingPercentEncoding ?? name
        await loadFiles()
    }

    // MARK: - Breadcrumb Path

    /// Path segments for breadcrumb navigation.
    /// Each segment is (displayName, stackIndex) where tapping navigates to that level.
    public var breadcrumbSegments: [(name: String, index: Int)] {
        guard !remotePathStack.isEmpty else {
            // At root with no navigation history
            return [(currentRootDisplayName, 0)]
        }

        var segments: [(name: String, index: Int)] = []

        // Root segment (data source name or local folder name)
        let rootName: String
        if let ds = activeDataSource {
            rootName = ds.name
        } else {
            let name = rootURL.lastPathComponent
            rootName = name.isEmpty ? rootURL.path : name
        }
        segments.append((rootName, 0))

        // Intermediate and current segments from path stack (skip index 0 = root)
        for i in 1..<remotePathStack.count {
            let path = remotePathStack[i]
            let name = (path as NSString).lastPathComponent
            segments.append((name.removingPercentEncoding ?? name, i))
        }

        return segments
    }

    /// Navigate to a specific breadcrumb level by stack index.
    public func navigateToBreadcrumb(index: Int) async {
        guard index >= 0, index < remotePathStack.count else { return }
        // Pop all entries after the target index
        remotePathStack = Array(remotePathStack.prefix(index + 1))
        let targetPath = remotePathStack.last ?? "/"
        currentRemotePath = targetPath
        canNavigateUp = remotePathStack.count > 1

        if let ds = activeDataSource, index == 0 {
            currentRootDisplayName = ds.name
        } else if activeRemoteAdapter == nil, index == 0 {
            let name = rootURL.lastPathComponent
            currentRootDisplayName = name.isEmpty ? rootURL.path : name
        } else {
            let name = (targetPath as NSString).lastPathComponent
            currentRootDisplayName = name.removingPercentEncoding ?? name
        }
        await loadFiles()
    }

    public func selectLocalFolder(_ folderURL: URL) async {
        let generation = beginSourceGeneration()
        let normalizedURL = folderURL.standardizedFileURL
        activeDataSource = nil
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
        folders = []
        remotePathStack = []
        canNavigateUp = false

        do {
            let values = try normalizedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                lastErrorMessage = "Selected item is not a folder."
                return
            }
        } catch {
            lastErrorMessage = "Unable to access selected folder: \(error.localizedDescription)"
            return
        }

        if securityScopedRootURL?.standardizedFileURL != normalizedURL {
            securityScopedRootURL?.stopAccessingSecurityScopedResource()
            securityScopedRootURL = nil
        }

        if normalizedURL.startAccessingSecurityScopedResource() {
            securityScopedRootURL = normalizedURL
        }

        rootURL = normalizedURL
        currentRootDisplayName = normalizedURL.lastPathComponent.isEmpty ? normalizedURL.path : normalizedURL.lastPathComponent
        await connectAndLoad(generation: generation)
    }

    public func useDefaultFolder() async {
        let generation = beginSourceGeneration()
        activeDataSource = nil
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
        folders = []
        remotePathStack = []
        canNavigateUp = false
        securityScopedRootURL?.stopAccessingSecurityScopedResource()
        securityScopedRootURL = nil
        rootURL = defaultRootURL
        currentRootDisplayName = defaultRootURL.lastPathComponent.isEmpty ? defaultRootURL.path : defaultRootURL.lastPathComponent
        await connectAndLoad(generation: generation)
    }

    private func connectAndLoad(generation: UInt64) async {
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
        do {
            try await localDataSource.connect(
                with: .init(sourceType: .local, rootPath: rootURL.path)
            )
            guard sourceGeneration == generation, activeDataSource == nil else { return }
            await loadFiles()
        } catch {
            guard sourceGeneration == generation, activeDataSource == nil else { return }
            files = []
            lastErrorMessage = "Failed to connect local data source: \(error.localizedDescription)"
            print("[FileBrowser] connect failed: \(error)")
        }
    }

    private func beginSourceGeneration() -> UInt64 {
        sourceGeneration &+= 1
        return sourceGeneration
    }

    private func isCurrentSource(_ generation: UInt64, dataSourceID: UUID) -> Bool {
        sourceGeneration == generation && activeDataSource?.id == dataSourceID
    }

    private func persistDataSources() {
        let records = savedDataSources.map(SavedDataSourceRecord.init)
        let data = try? JSONEncoder().encode(records)
        savedDataSourceStore.saveSavedDataSourceRecords(data)
    }

    private func applySortToFiles() {
        let criteria = sortCriteria
        let sorted: [FileBrowsingDomain.MediaFile]
        switch criteria.key {
        case .name:
            sorted = files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modifiedDate:
            sorted = files.sorted { $0.modifiedAt < $1.modifiedAt }
        case .size:
            sorted = files.sorted { $0.sizeInBytes < $1.sizeInBytes }
        }
        switch criteria.order {
        case .ascending:
            files = sorted
        case .descending:
            files = sorted.reversed()
        }
    }

    private func makeStableIdentifier(
        for file: FileBrowsingDomain.MediaFile,
        playableURL: URL
    ) -> String {
        let path: String
        let serverFingerprint: String?

        if let dataSource = activeDataSource {
            let logicalDirectory = currentRemotePath == "/" ? "" : currentRemotePath
            path = "\(logicalDirectory)/\(file.name)"
            let host = dataSource.connectionInfo.host ?? dataSource.name
            let port = dataSource.connectionInfo.port.map(String.init) ?? "-"
            serverFingerprint = "\(dataSource.sourceType.rawValue):\(host):\(port)"
        } else {
            path = playableURL.path
            serverFingerprint = nil
        }

        return "\(path)|\(file.sizeInBytes)|\(serverFingerprint ?? "local")"
    }

    private func loadProgressForFiles() {
        let currentFiles = files
        let currentGeneration = sourceGeneration
        Task { [weak self] in
            guard let self else { return }
            var map: [UUID: VideoCardViewingState] = [:]
            for file in currentFiles {
                let identity: MediaIdentity?
                if let dataSource = self.activeDataSource {
                    identity = .remote(
                        sourceKey: dataSource.connectionInfo.mediaIdentitySourceKey,
                        canonicalPath: file.url.path
                    )
                } else if self.activeDataSource == nil {
                    identity = VersionedMediaIdentity.localIdentity(file.url)
                } else {
                    identity = nil
                }
                guard let identity,
                      let state = await self.viewingStateProvider(identity) else { continue }
                map[file.id] = state
            }
            guard self.sourceGeneration == currentGeneration,
                  self.files.map(\.id) == currentFiles.map(\.id) else { return }
            self.fileViewingStates = map
        }
    }

    public func refreshViewingStates() {
        loadProgressForFiles()
    }

    private static func isNetworkRecoverableError(_ error: Error) -> Bool {
        if let smbError = error as? SMBError {
            switch smbError {
            case .networkFailed, .notConnected: return true
            default: return false
            }
        }
        if let webDAVError = error as? WebDAVError {
            switch webDAVError {
            case .notConnected: return true
            case .requestFailed(let code) where code >= 500: return true
            default: return false
            }
        }
        return (error as NSError).domain == NSURLErrorDomain
    }
}

private nonisolated final class CredentialOverlayStore: CredentialStoring, @unchecked Sendable {
    private let base: any CredentialStoring
    private let sourceID: String
    private let credential: StorageCredential

    init(
        base: any CredentialStoring,
        sourceID: String,
        credential: StorageCredential
    ) {
        self.base = base
        self.sourceID = sourceID
        self.credential = credential
    }

    func saveCredential(for sourceID: String, credential: StorageCredential) throws {
        try base.saveCredential(for: sourceID, credential: credential)
    }

    func loadCredential(for sourceID: String) throws -> StorageCredential? {
        if sourceID == self.sourceID {
            return credential
        }
        return try base.loadCredential(for: sourceID)
    }

    func deleteCredential(for sourceID: String) throws {
        try base.deleteCredential(for: sourceID)
    }
}

private struct SavedDataSourceRecord: Codable {
    let id: String
    let name: String
    let sourceType: String
    let connectionInfo: SavedConnectionInfoRecord

    init(_ dataSource: FileBrowsingDomain.DataSource) {
        self.id = dataSource.id.uuidString
        self.name = dataSource.name
        self.sourceType = dataSource.sourceType.rawValue
        self.connectionInfo = SavedConnectionInfoRecord(dataSource.connectionInfo)
    }

    var domainValue: FileBrowsingDomain.DataSource? {
        guard let id = UUID(uuidString: id),
              let sourceType = FileBrowsingDomain.SourceType(rawValue: sourceType),
              let connectionInfo = connectionInfo.domainValue(fallbackSourceType: sourceType)
        else {
            return nil
        }

        return FileBrowsingDomain.DataSource(
            id: id,
            name: name,
            sourceType: sourceType,
            connectionInfo: connectionInfo
        )
    }
}

private struct SavedConnectionInfoRecord: Codable {
    let sourceType: String
    let address: String?
    let scheme: String?
    let host: String?
    let port: Int?
    let username: String?
    let rootPath: String

    init(_ connectionInfo: FileBrowsingDomain.ConnectionInfo) {
        self.sourceType = connectionInfo.sourceType.rawValue
        self.address = connectionInfo.address
        self.scheme = connectionInfo.scheme
        self.host = connectionInfo.host
        self.port = connectionInfo.port
        self.username = connectionInfo.username
        self.rootPath = connectionInfo.rootPath
    }

    func domainValue(
        fallbackSourceType: FileBrowsingDomain.SourceType
    ) -> FileBrowsingDomain.ConnectionInfo? {
        let resolvedSourceType = FileBrowsingDomain.SourceType(rawValue: sourceType) ?? fallbackSourceType

        return FileBrowsingDomain.ConnectionInfo(
            sourceType: resolvedSourceType,
            address: address,
            scheme: scheme,
            host: host,
            port: port,
            username: username,
            rootPath: rootPath
        )
    }
}
