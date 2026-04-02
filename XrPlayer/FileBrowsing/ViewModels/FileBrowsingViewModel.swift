import Foundation
import Observation

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
    public var detailNavigationRequest: PlaybackLaunchRequest?

    private let localDataSource: LocalDataSourceAdapter
    private let fileManager: FileManager
    public let credentialStoreForConfig: CredentialStoring
    private let savedDataSourceStore: SavedDataSourceRecordStoring
    private var credentialStore: CredentialStoring { credentialStoreForConfig }
    private let importQueue = DispatchQueue(label: "xrplayer.fileimport.io", qos: .utility)
    private let onPlayFile: @MainActor (PlaybackLaunchRequest) -> Void
    private let onPrepareFile: (@MainActor (PlaybackLaunchRequest) -> Void)?
    private let defaultRootURL: URL
    private let localDataSourceID = UUID()
    private var rootURL: URL
    private var securityScopedRootURL: URL?
    private var activeRemoteAdapter: (any DataSourceConnecting & FileProviding)?
    private var remotePathStack: [String] = []

    public init(
        localDataSource: LocalDataSourceAdapter,
        fileManager: FileManager = .default,
        credentialStore: CredentialStoring = KeychainStore(),
        savedDataSourceStore: SavedDataSourceRecordStoring = SavedDataSourceStore(),
        onPlayFile: @escaping @MainActor (PlaybackLaunchRequest) -> Void,
        onPrepareFile: (@MainActor (PlaybackLaunchRequest) -> Void)? = nil
    ) {
        self.localDataSource = localDataSource
        self.fileManager = fileManager
        self.credentialStoreForConfig = credentialStore
        self.savedDataSourceStore = savedDataSourceStore
        self.onPlayFile = onPlayFile
        self.onPrepareFile = onPrepareFile
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.defaultRootURL = documentsURL
        self.rootURL = documentsURL
        self.currentRootDisplayName = documentsURL.lastPathComponent.isEmpty ? documentsURL.path : documentsURL.lastPathComponent
        self.localDataSource.ownerDataSourceID = localDataSourceID

        Task { [weak self] in
            await self?.connectAndLoad()
        }

        loadSavedDataSources()
    }

    public func saveCredential(for dataSource: FileBrowsingDomain.DataSource, username: String, password: String) {
        let sourceID = dataSource.credentialSourceID
        do {
            try credentialStore.saveCredential(
                for: sourceID,
                credential: StorageCredential(username: username, password: password)
            )
        } catch {
            print("[FileBrowser] Failed to save credential for \(sourceID): \(error)")
        }
    }

    public func deleteCredential(for dataSource: FileBrowsingDomain.DataSource) {
        do {
            try credentialStore.deleteCredential(for: dataSource.credentialSourceID)
        } catch {
            print("[FileBrowser] Failed to delete credential for \(dataSource.credentialSourceID): \(error)")
        }
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
        deleteCredential(for: removedSource)
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

    public func connectToDataSource(_ ds: FileBrowsingDomain.DataSource) async {
        activeDataSource = ds

        let adapter: any DataSourceConnecting & FileProviding
        switch ds.connectionInfo.sourceType {
        case .webDAV:
            let webDAV = WebDAVDataSourceAdapter(credentialStore: credentialStore)
            webDAV.ownerDataSourceID = ds.id
            adapter = webDAV
        case .smb:
            let smb = SMBDataSourceAdapter(credentialStore: credentialStore)
            smb.ownerDataSourceID = ds.id
            adapter = smb
        case .local:
            await useDefaultFolder()
            return
        case .photoLibrary:
            activeDataSource = nil
            lastErrorMessage = "Photo Library source is not implemented yet."
            return
        }

        activeRemoteAdapter?.disconnect()
        do {
            try await adapter.connect(with: ds.connectionInfo)
            activeRemoteAdapter = adapter
            let rootPath = ds.connectionInfo.rootPath
            remotePathStack = [rootPath]
            currentRemotePath = rootPath
            canNavigateUp = false
            isLoading = true
            defer { isLoading = false }

            let remoteFiles = try await adapter.listContents(at: rootPath)
            let remoteFolders = try await adapter.listFolders(at: rootPath)
            files = remoteFiles
            folders = remoteFolders
            currentRootDisplayName = ds.name
            lastErrorMessage = nil
        } catch {
            activeRemoteAdapter = nil
            activeDataSource = nil
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
        isLoading = true
        defer { isLoading = false }

        if let remoteAdapter = activeRemoteAdapter {
            do {
                files = try await remoteAdapter.listContents(at: currentRemotePath)
                folders = try await remoteAdapter.listFolders(at: currentRemotePath)
                lastErrorMessage = nil
            } catch {
                files = []
                folders = []
                lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
            }
            applySortToFiles()
            return
        }

        do {
            files = try await localDataSource.listContents(at: ".")
            lastErrorMessage = nil
        } catch {
            files = []
            lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
            print("[FileBrowser] loadFiles failed: \(error)")
        }
        applySortToFiles()
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
        Task { [weak self] in
            guard let self else { return }
            do {
                let request = try await playbackRequest(for: file)
                print("[FileBrowser] selected file: \(request.url.path)")
                if let onPrepareFile {
                    self.detailNavigationRequest = request
                    onPrepareFile(request)
                } else {
                    onPlayFile(request)
                }
            } catch {
                lastErrorMessage = "Failed to open \"\(file.name)\": \(error.localizedDescription)"
                print("[FileBrowser] selectFile failed for \(file.name): \(error)")
                return
            }
        }
    }

    public func playbackRequest(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> PlaybackLaunchRequest {
        let playableURL: URL
        if let activeRemoteAdapter {
            playableURL = try await activeRemoteAdapter.resolvePlayableURL(for: file)
        } else {
            playableURL = try await localDataSource.resolvePlayableURL(for: file)
        }

        let fileIdentifier = makeFileIdentifier(for: file, playableURL: playableURL)
        let metadata = PlaybackMediaMetadata(fileSizeInBytes: file.sizeInBytes)
        return PlaybackLaunchRequest(
            url: playableURL,
            displayName: file.name,
            fileIdentifier: fileIdentifier,
            initialMetadata: metadata
        )
    }

    public func navigateToFolder(_ folder: FileBrowsingDomain.MediaFolder) async {
        guard activeRemoteAdapter != nil else { return }
        remotePathStack.append(folder.path)
        currentRemotePath = folder.path
        canNavigateUp = remotePathStack.count > 1
        currentRootDisplayName = folder.name
        await loadFiles()
    }

    public func navigateUp() async {
        guard activeRemoteAdapter != nil, remotePathStack.count > 1 else { return }
        remotePathStack.removeLast()
        let previousPath = remotePathStack.last ?? "/"
        currentRemotePath = previousPath
        canNavigateUp = remotePathStack.count > 1

        if let ds = activeDataSource, remotePathStack.count == 1 {
            currentRootDisplayName = ds.name
        } else {
            let name = (previousPath as NSString).lastPathComponent
            currentRootDisplayName = name.removingPercentEncoding ?? name
        }
        await loadFiles()
    }

    public func selectLocalFolder(_ folderURL: URL) async {
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
        await connectAndLoad()
    }

    public func useDefaultFolder() async {
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
        await connectAndLoad()
    }

    public func importLocalFiles(_ sourceURLs: [URL]) async {
        guard sourceURLs.isEmpty == false else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try fileManager.createDirectory(at: defaultRootURL, withIntermediateDirectories: true)
        } catch {
            lastErrorMessage = "Failed to prepare Documents folder: \(error.localizedDescription)"
            return
        }

        var importedCount = 0
        var failedNames: [String] = []
        var skippedDuplicates: [String] = []

        for sourceURL in sourceURLs {
            let normalizedURL = sourceURL.standardizedFileURL

            guard FileBrowsingDomain.FileFilter.playable.matches(fileURL: normalizedURL) else {
                failedNames.append(normalizedURL.lastPathComponent)
                continue
            }

            // Skip if a file with the same name already exists in Documents
            let destinationURL = defaultRootURL.appendingPathComponent(normalizedURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                skippedDuplicates.append(normalizedURL.lastPathComponent)
                continue
            }

            let hasSecurityAccess = normalizedURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityAccess {
                    normalizedURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try await copyItem(at: normalizedURL, to: destinationURL)
                importedCount += 1
            } catch {
                failedNames.append(normalizedURL.lastPathComponent)
                print("[FileBrowser] import failed for \(normalizedURL.lastPathComponent): \(error)")
            }
        }

        await useDefaultFolder()

        var messages: [String] = []
        if importedCount > 0 { messages.append("Imported \(importedCount) file(s).") }
        if skippedDuplicates.isEmpty == false { messages.append("Skipped duplicates: \(skippedDuplicates.joined(separator: ", "))") }
        if failedNames.isEmpty == false { messages.append("Failed: \(failedNames.joined(separator: ", "))") }

        if importedCount == 0 && skippedDuplicates.isEmpty == false {
            lastErrorMessage = messages.joined(separator: " ")
        } else if messages.count > 1 || importedCount == 0 {
            lastErrorMessage = messages.isEmpty ? "No files were imported." : messages.joined(separator: " ")
        } else {
            lastErrorMessage = nil
        }
    }

    private func connectAndLoad() async {
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
        do {
            try await localDataSource.connect(
                with: .init(sourceType: .local, rootPath: rootURL.path)
            )
            await loadFiles()
        } catch {
            files = []
            lastErrorMessage = "Failed to connect local data source: \(error.localizedDescription)"
            print("[FileBrowser] connect failed: \(error)")
        }
    }

    private func nextAvailableDocumentURL(for sourceURL: URL) -> URL {
        let ext = sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = defaultRootURL.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1

        while fileManager.fileExists(atPath: candidate.path) {
            let filename: String
            if ext.isEmpty {
                filename = "\(stem) \(counter)"
            } else {
                filename = "\(stem) \(counter).\(ext)"
            }
            candidate = defaultRootURL.appendingPathComponent(filename)
            counter += 1
        }

        return candidate
    }

    private func copyItem(at sourceURL: URL, to destinationURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            importQueue.async { [fileManager] in
                do {
                    try fileManager.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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

    private func makeFileIdentifier(
        for file: FileBrowsingDomain.MediaFile,
        playableURL: URL
    ) -> PersistenceDomain.FileIdentifier {
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

        return PersistenceDomain.FileIdentifier.make(
            path: path,
            sizeInBytes: file.sizeInBytes,
            serverFingerprint: serverFingerprint
        )
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
