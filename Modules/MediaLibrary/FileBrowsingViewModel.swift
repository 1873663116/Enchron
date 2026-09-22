import Foundation
import MediaSource
import Observation
import OSLog

@MainActor
@Observable
public final class FileBrowsingViewModel {
    public var playbackPreparation = MediaSourcePreparation()

    public var files: [FileBrowsingDomain.MediaFile] = []
    public var folders: [FileBrowsingDomain.MediaFolder] = []
    public var isLoading: Bool = false
    public var lastErrorMessage: String?
    public var sortCriteria: FileBrowsingDomain.SortCriteria {
        get { uiState.sortCriteria }
        set { uiState.sortCriteria = newValue }
    }
    public private(set) var currentRootDisplayName: String = "Documents"
    public private(set) var currentRemotePath: String = "/"
    public private(set) var canNavigateUp: Bool = false

    public var savedDataSources: [FileBrowsingDomain.DataSource] = []
    public var activeDataSource: FileBrowsingDomain.DataSource?

    public var detailNavigationRequest: MediaPlaybackItem?

    public private(set) var fileViewingStates: [UUID: VideoCardViewingState] = [:]

    public var searchText: String = ""

    public var displayedFiles: [FileBrowsingDomain.MediaFile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public var displayedFolders: [FileBrowsingDomain.MediaFolder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return folders }
        return folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public private(set) var canNavigateForward: Bool = false

    private var settledLevel: LevelIdentity?

    private struct LevelIdentity: Equatable {
        let generation: UInt64
        let dataSourceID: UUID?
        let path: String
    }

    private var currentLevel: LevelIdentity {
        LevelIdentity(
            generation: sourceGeneration,
            dataSourceID: activeDataSource?.id,
            path: currentRemotePath
        )
    }

    public var currentLevelHasSettled: Bool { settledLevel == currentLevel }

    private let localDataSource: any LocalFileSource
    private let uiState: MediaLibraryUIState
    private let logger = Logger(subsystem: "app.enchron", category: "FileBrowser")
    private let fileManager: FileManager
    private let credentialStoreForConfig: CredentialStoring
    private let savedDataSourceStore: SavedDataSourceRecordStoring
    private let viewingStateProvider: MediaViewingStateProvider
    private let durationProbe: MediaDurationProbe?
    private var credentialStore: CredentialStoring { credentialStoreForConfig }
    private let onPlayFile: @MainActor (MediaPlaybackItem) -> Void
    private let onPrepareFile: (@MainActor (MediaPlaybackItem) -> Void)?
    private let defaultRootURL: URL
    public let localDataSourceID: UUID
    private var rootURL: URL
    private var securityScopedRootURL: URL?
    private var activeRemoteAdapter: (any DataSourceConnecting & FileProviding)?
    private var remotePathStack: [String] = []
    private var forwardPathStack: [String] = []
    private var reconnectAttempted: Bool = false
    private var sourceGeneration: UInt64 = 0
    private var playbackCollection: [FileBrowsingDomain.MediaFile] = []
    private var currentPlaybackFileID: UUID?

    private let makeRemoteAdapter: (@MainActor (
        FileBrowsingDomain.DataSource,
        any CredentialStoring
    ) -> (any DataSourceConnecting & FileProviding)?)?

    init(
        localDataSource: any LocalFileSource,
        uiState: MediaLibraryUIState = MediaLibraryUIState(),
        fileManager: FileManager = .default,
        credentialStore: CredentialStoring = KeychainStore(),
        savedDataSourceStore: SavedDataSourceRecordStoring = SavedDataSourceStore(),
        viewingStateProvider: @escaping MediaViewingStateProvider = { _ in nil },
        durationProbe: MediaDurationProbe? = nil,
        localDataSourceID: UUID = UUID(),
        makeRemoteAdapter: (@MainActor (
            FileBrowsingDomain.DataSource,
            any CredentialStoring
        ) -> (any DataSourceConnecting & FileProviding)?)? = nil,
        onPlayFile: @escaping @MainActor (MediaPlaybackItem) -> Void,
        onPrepareFile: (@MainActor (MediaPlaybackItem) -> Void)? = nil
    ) {
        self.localDataSource = localDataSource
        self.uiState = uiState
        self.fileManager = fileManager
        self.credentialStoreForConfig = credentialStore
        self.savedDataSourceStore = savedDataSourceStore
        self.viewingStateProvider = viewingStateProvider
        self.durationProbe = durationProbe
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
        uiState.observeSortCriteriaChanges { [weak self] _ in
            self?.applySortToLevel()
        }
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
#if DEBUG
            print("[FileBrowser] Failed to delete credential for \(dataSource.credentialSourceID): \(error)")
#endif
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
    ) async -> RemoteConnectionResult {
        let generation = beginSourceGeneration()
        activeDataSource = ds
        isLoading = true
        lastErrorMessage = nil
        enterLevel()
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
                return .connected
            }
        }

        activeRemoteAdapter?.disconnect()
        do {
            try await adapter.connect(with: ds.connectionInfo)
            guard isCurrentSource(generation, dataSourceID: ds.id) else {
                adapter.disconnect()
                return .connected
            }
            activeRemoteAdapter = adapter

            let remoteFiles = try await adapter.listContents(at: rootPath)
            let remoteFolders = try await adapter.listFolders(at: rootPath)
            guard isCurrentSource(generation, dataSourceID: ds.id) else {
                adapter.disconnect()
                return .connected
            }
            files = remoteFiles
            folders = remoteFolders
            currentRootDisplayName = ds.name
            lastErrorMessage = nil
            isLoading = false
            settleCurrentLevel()
            return .connected
        } catch {
            adapter.disconnect()
            let result = RemoteConnectionResult.failed(Self.connectionFailure(for: error))
            guard isCurrentSource(generation, dataSourceID: ds.id) else { return result }
            isLoading = false
            activeRemoteAdapter = nil
            settleCurrentLevel()
            return result
        }
    }

    static func connectionFailure(for error: any Error) -> RemoteConnectionFailure {
        if let failure = error as? RemoteConnectionFailure {
            return failure
        }

        if error is FileBrowsingDomain.ConnectionInfoError {
            return .invalidAddress
        }

        if let webDAVError = error as? WebDAVError {
            switch webDAVError {
            case .requestFailed(let code) where code == 401 || code == 403:
                return .credentialsRejected
            case .invalidConnectionInfo:
                return .invalidAddress
            case .notConnected, .invalidResponse, .requestFailed, .malformedResponse,
                 .streamingFailed:
                return .serverUnreachable
            }
        }

        if let smbError = error as? SMBError {
            return SMBDataSourceAdapter.connectionFailure(for: smbError)
        }

        if let code = urlFailureCode(in: error) {
            switch URLError.Code(rawValue: code) {
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return .credentialsRejected
            case .badURL, .unsupportedURL:
                return .invalidAddress
            default:
                return .serverUnreachable
            }
        }

        return .serverUnreachable
    }

    private static func urlFailureCode(in error: any Error) -> Int? {
        var current: NSError? = error as NSError
        var visited: Set<ObjectIdentifier> = []

        while let candidate = current {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { return nil }
            if candidate.domain == NSURLErrorDomain {
                return candidate.code
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return nil
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
                    await reconnectAndSurfaceFailure(to: ds)
                    reconnectAttempted = false
                    return
                }
                lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
            }
            applySortToLevel()
            loadProgressForFiles()
            settleCurrentLevel()
            return
        }

        if let dataSource = activeDataSource {
            await reconnectAndSurfaceFailure(to: dataSource)
            return
        }

        let localPath = remotePathStack.isEmpty ? "." : currentRemotePath
        do {
            let newFiles = try await localDataSource.listContents(at: localPath)
            let newFolders = try await localDataSource.listFolders(at: localPath)
            guard sourceGeneration == generation, activeDataSource == nil else { return }
            mergeFiles(newFiles)
            mergeFolders(newFolders)
            lastErrorMessage = nil
        } catch {
            guard sourceGeneration == generation, activeDataSource == nil else { return }
            lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
#if DEBUG
            print("[FileBrowser] loadFiles failed: \(error)")
#endif
        }
        applySortToLevel()
        loadProgressForFiles()
        settleCurrentLevel()
    }

    private func reconnectAndSurfaceFailure(
        to dataSource: FileBrowsingDomain.DataSource
    ) async {
        let result = await connectToDataSource(dataSource)
        guard case .failed(let failure) = result,
              activeDataSource?.id == dataSource.id,
              activeRemoteAdapter == nil,
              isLoading == false else { return }
        lastErrorMessage = failure.localizedDescription
    }

    private func settleCurrentLevel() {
        settledLevel = currentLevel
    }

    private func enterLevel() {
        settledLevel = nil
        files = []
        folders = []
    }

    private func mergeFiles(_ newFiles: [FileBrowsingDomain.MediaFile]) {
        let newByID = Dictionary(newFiles.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let oldIDs = Set(files.map(\.id))
        let newIDs = Set(newFiles.map(\.id))

        files.removeAll { !newIDs.contains($0.id) }

        files = files.map { oldFile in
            newByID[oldFile.id] ?? oldFile
        }

        for file in newFiles where !oldIDs.contains(file.id) {
            files.append(file)
        }
    }

    private func mergeFolders(_ newFolders: [FileBrowsingDomain.MediaFolder]) {
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
            do {
                let request = try await playbackPreparation.resolve {
                    try await Task.sleep(for: .milliseconds(20))
                    return try await self.playbackItem(for: file)
                }
                logger.info("file selected name=\(file.name, privacy: .public)")
                if let onPrepareFile {
                    self.detailNavigationRequest = request
                    onPrepareFile(request)
                } else {
                    onPlayFile(request)
                }
            } catch is CancellationError {
                return
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
        let externalSubtitles = await resolvedExternalSubtitleSources(
            for: file,
            provider: activeRemoteAdapter ?? localDataSource,
            dataSource: activeDataSource
        )
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
            accessLease: sourceAccess,
            byteStreamHandle: resolvedSource.byteStreamHandle,
            externalSubtitleSources: externalSubtitles.sources,
            externalSubtitleResolutionFailed: externalSubtitles.hadFailures
        )
    }

    public func artworkURL(for file: FileBrowsingDomain.MediaFile) -> URL? {
        let identity: MediaIdentity?
        if let dataSource = activeDataSource {
            identity = .remote(
                sourceKey: dataSource.connectionInfo.mediaIdentitySourceKey,
                canonicalPath: file.url.path
            )
        } else {
            identity = VersionedMediaIdentity.localIdentity(file.url)
        }
        guard let identity else { return nil }
        return ArtworkStore.shared.fileURL(for: ArtworkKey(mediaIdentity: identity))
    }

    private func resolvedExternalSubtitleSources(
        for mediaFile: FileBrowsingDomain.MediaFile,
        provider: any FileProviding,
        dataSource: FileBrowsingDomain.DataSource?
    ) async -> ExternalSubtitleResolution {
        let directoryPath = mediaFile.url.deletingLastPathComponent().path
        let listedFiles: [FileBrowsingDomain.MediaFile]
        do {
            listedFiles = try await provider.listSubtitleFiles(at: directoryPath)
        } catch {
            logger.error(
                "external subtitle discovery failed error=\(error.localizedDescription, privacy: .public)"
            )
            return ExternalSubtitleResolution(
                sources: [],
                hadFailures: true
            )
        }
        let candidates = ExternalSubtitleAssociation.matching(
            mediaFile: mediaFile,
            subtitleFiles: listedFiles
        )
        var sources: [ResolvedExternalSubtitleSource] = []
        var hadFailures = false
        for candidate in candidates {
            let resolved: ResolvedMediaSource
            do {
                resolved = try await provider.resolveSubtitleSource(for: candidate)
            } catch {
                hadFailures = true
                logger.error(
                    "external subtitle resolution failed source=\(candidate.name, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                continue
            }
            let versionedIdentity = externalSubtitleIdentity(
                for: candidate,
                resolvedURL: resolved.url,
                dataSource: dataSource
            )
            let sourceID = versionedIdentity?.mediaIdentity.storageKey
                ?? fallbackExternalSubtitleIdentity(
                    for: candidate,
                    dataSource: dataSource
                ).storageKey
            sources.append(
                ResolvedExternalSubtitleSource(
                    id: sourceID,
                    url: resolved.url,
                    displayName: candidate.name,
                    versionedIdentity: versionedIdentity,
                    accessLease: resolved.accessLease,
                    byteStreamHandle: resolved.byteStreamHandle
                )
            )
        }
        return ExternalSubtitleResolution(
            sources: sources,
            hadFailures: hadFailures
        )
    }

    private func externalSubtitleIdentity(
        for file: FileBrowsingDomain.MediaFile,
        resolvedURL: URL,
        dataSource: FileBrowsingDomain.DataSource?
    ) -> VersionedMediaIdentity? {
        if let dataSource {
            return .remote(
                sourceKey: dataSource.connectionInfo.mediaIdentitySourceKey,
                canonicalPath: file.url.path,
                entityTag: file.remoteEntityTag,
                sizeInBytes: file.sizeInBytes,
                modifiedAt: file.modifiedAt
            )
        }
        return .local(resolvedURL)
    }

    private func fallbackExternalSubtitleIdentity(
        for file: FileBrowsingDomain.MediaFile,
        dataSource: FileBrowsingDomain.DataSource?
    ) -> MediaIdentity {
        if let dataSource {
            return .remote(
                sourceKey: dataSource.connectionInfo.mediaIdentitySourceKey,
                canonicalPath: file.url.path
            )
        }
        return .localPathFallback(canonicalPath: file.url.absoluteString)
    }

    public var hasNextPlaybackItem: Bool {
        guard let currentPlaybackFileID,
              let index = playbackCollection.firstIndex(where: { $0.id == currentPlaybackFileID })
        else { return false }
        return playbackCollection.indices.contains(index + 1)
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
        case .local:
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

    func resolveExternalSubtitleSources(
        dataSourceID: UUID,
        path: String,
        reference: FileBrowsingDomain.MediaReference
    ) async throws -> ExternalSubtitleResolution {
        guard let url = URL(string: path) else {
            throw MediaReferenceResolver.ResolutionError.unavailableSource
        }
        let file = FileBrowsingDomain.MediaFile(
            name: reference.name,
            sizeInBytes: reference.sizeInBytes,
            modifiedAt: reference.modifiedAt,
            fileExtension: reference.fileExtension,
            url: url,
            remoteEntityTag: reference.remoteEntityTag
        )
        if dataSourceID == localDataSourceID {
            return await resolvedExternalSubtitleSources(
                for: file,
                provider: localDataSource,
                dataSource: nil
            )
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
        case .local:
            throw MediaReferenceResolver.ResolutionError.unavailableSource
        }
        do {
            try await adapter.connect(with: dataSource.connectionInfo)
            let sources = await resolvedExternalSubtitleSources(
                for: file,
                provider: adapter,
                dataSource: dataSource
            )
            adapter.disconnect()
            return sources
        } catch {
            adapter.disconnect()
            throw error
        }
    }

    public func navigateToFolder(_ folder: FileBrowsingDomain.MediaFolder) async {
        if remotePathStack.isEmpty {
            remotePathStack.append(activeRemoteAdapter != nil ? currentRemotePath : "/")
        }
        remotePathStack.append(folder.path)
        currentRemotePath = folder.path
        canNavigateUp = remotePathStack.count > 1
        forwardPathStack.removeAll()
        canNavigateForward = false
        currentRootDisplayName = folder.name
        enterLevel()
        await loadFiles()
    }

    public func navigateUp() async {
        guard remotePathStack.count > 1 else { return }
        let leftLevel = remotePathStack.removeLast()
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
        enterLevel()
        await loadFiles()
    }

    public func navigateForward() async {
        guard let next = forwardPathStack.popLast() else { return }
        remotePathStack.append(next)
        currentRemotePath = next
        canNavigateUp = remotePathStack.count > 1
        canNavigateForward = !forwardPathStack.isEmpty
        let name = (next as NSString).lastPathComponent
        currentRootDisplayName = name.removingPercentEncoding ?? name
        enterLevel()
        await loadFiles()
    }

    public var breadcrumbSegments: [(name: String, index: Int)] {
        guard !remotePathStack.isEmpty else {
            return [(currentRootDisplayName, 0)]
        }

        var segments: [(name: String, index: Int)] = []

        let rootName: String
        if let ds = activeDataSource {
            rootName = ds.name
        } else {
            let name = rootURL.lastPathComponent
            rootName = name.isEmpty ? rootURL.path : name
        }
        segments.append((rootName, 0))

        for i in 1..<remotePathStack.count {
            let path = remotePathStack[i]
            let name = (path as NSString).lastPathComponent
            segments.append((name.removingPercentEncoding ?? name, i))
        }

        return segments
    }

    public func navigateToBreadcrumb(index: Int) async {
        guard index >= 0, index < remotePathStack.count else { return }
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
        enterLevel()
        await loadFiles()
    }

    public func selectLocalFolder(_ folderURL: URL) async {
        let generation = beginSourceGeneration()
        let normalizedURL = folderURL.standardizedFileURL
        activeDataSource = nil
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
        enterLevel()
        remotePathStack = []
        canNavigateUp = false

        do {
            let values = try normalizedURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                lastErrorMessage = "Selected item is not a folder."
                settleCurrentLevel()
                return
            }
        } catch {
            lastErrorMessage = "Unable to access selected folder: \(error.localizedDescription)"
            settleCurrentLevel()
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
        enterLevel()
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
#if DEBUG
            print("[FileBrowser] connect failed: \(error)")
#endif
            settleCurrentLevel()
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

    private func applySortToLevel() {
        let criteria = sortCriteria
        files = criteria.sorted(files)
        folders = criteria.sorted(folders)
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
                  Set(self.files.map(\.id)) == Set(currentFiles.map(\.id)) else { return }
            self.fileViewingStates = map
            guard let durationProbe = self.durationProbe else { return }
            for file in currentFiles where map[file.id] == nil {
                guard self.sourceGeneration == currentGeneration else { return }
                guard let duration = await self.probeDuration(for: file, using: durationProbe) else { continue }
                guard self.sourceGeneration == currentGeneration,
                      Set(self.files.map(\.id)) == Set(currentFiles.map(\.id)),
                      self.fileViewingStates[file.id] == nil else { continue }
                self.fileViewingStates[file.id] = VideoCardViewingState(
                    positionSeconds: 0,
                    durationSeconds: duration,
                    isCompleted: false
                )
            }
        }
    }

    private func probeDuration(
        for file: FileBrowsingDomain.MediaFile,
        using probe: MediaDurationProbe
    ) async -> Double? {
        let resolved: ResolvedMediaSource
        do {
            if let activeRemoteAdapter {
                resolved = try await activeRemoteAdapter.resolvePlayableSource(for: file)
            } else {
                resolved = try await localDataSource.resolvePlayableSource(for: file)
            }
        } catch {
            return nil
        }
        defer { resolved.byteStreamHandle?.release() }
        let identity: VersionedMediaIdentity?
        if let dataSource = activeDataSource {
            identity = VersionedMediaIdentity.remote(
                sourceKey: dataSource.connectionInfo.mediaIdentitySourceKey,
                canonicalPath: file.url.path,
                entityTag: file.remoteEntityTag,
                sizeInBytes: file.sizeInBytes,
                modifiedAt: file.modifiedAt
            )
        } else {
            identity = VersionedMediaIdentity.local(resolved.url)
        }
        guard let identity else { return nil }
        return await probe(resolved, identity)
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
