import Foundation
import Observation

@MainActor
@Observable
public final class FileBrowsingViewModel {
    public struct ReconnectPolicy: Sendable, Equatable {
        public let maxAttempts: Int
        public let initialDelaySeconds: Double
        public let backoffMultiplier: Double
        public let maxDelaySeconds: Double

        public init(
            maxAttempts: Int = 3,
            initialDelaySeconds: Double = 1,
            backoffMultiplier: Double = 2,
            maxDelaySeconds: Double = 8
        ) {
            self.maxAttempts = max(1, maxAttempts)
            self.initialDelaySeconds = max(0.1, initialDelaySeconds)
            self.backoffMultiplier = max(1, backoffMultiplier)
            self.maxDelaySeconds = max(self.initialDelaySeconds, maxDelaySeconds)
        }
    }

    public typealias RemoteAdapterFactory =
        (FileBrowsingDomain.SourceType, CredentialStoring) -> (any DataSourceConnecting & FileProviding)?

    public var files: [FileBrowsingDomain.MediaFile] = []
    public var isLoading: Bool = false
    public var lastErrorMessage: String?
    public var reconnectStatusMessage: String?
    public private(set) var currentRootDisplayName: String = "Documents"

    public var savedDataSources: [FileBrowsingDomain.DataSource] = []
    public var activeDataSource: FileBrowsingDomain.DataSource?

    private let localDataSource: LocalDataSourceAdapter
    private let fileManager: FileManager
    private let credentialStore: CredentialStoring
    private let adapterFactory: RemoteAdapterFactory
    private let reconnectPolicy: ReconnectPolicy
    private let preferences: UserDefaults
    private static let savedDataSourcesKey = "xrplayer.savedDataSources"
    private static let lastConnectedDataSourceIDKey = "xrplayer.lastConnectedDataSourceID"
    private let importQueue = DispatchQueue(label: "xrplayer.fileimport.io", qos: .utility)
    private let onPlayFile: @MainActor (URL) -> Void
    private let defaultRootURL: URL
    private var rootURL: URL
    private var securityScopedRootURL: URL?
    private var activeRemoteAdapter: (any DataSourceConnecting & FileProviding)?
    private var reconnectTask: Task<Void, Never>?

    public init(
        localDataSource: LocalDataSourceAdapter,
        fileManager: FileManager = .default,
        credentialStore: CredentialStoring? = nil,
        reconnectPolicy: ReconnectPolicy? = nil,
        preferences: UserDefaults = .standard,
        adapterFactory: RemoteAdapterFactory? = nil,
        onPlayFile: @escaping @MainActor (URL) -> Void
    ) {
        self.localDataSource = localDataSource
        self.fileManager = fileManager
        self.credentialStore = credentialStore ?? KeychainStore()
        self.reconnectPolicy = reconnectPolicy ?? .init()
        self.preferences = preferences
        self.adapterFactory = adapterFactory ?? { sourceType, credentialStore in
            switch sourceType {
            case .webDAV:
                return WebDAVDataSourceAdapter(credentialStore: credentialStore)
            case .smb:
                return SMBDataSourceAdapter(credentialStore: credentialStore)
            case .local, .photoLibrary:
                return nil
            }
        }
        self.onPlayFile = onPlayFile
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.defaultRootURL = documentsURL
        self.rootURL = documentsURL
        self.currentRootDisplayName = documentsURL.lastPathComponent.isEmpty ? documentsURL.path : documentsURL.lastPathComponent

        loadSavedDataSources()

        Task { [weak self] in
            await self?.restoreInitialDataSource()
        }
    }

    public func addDataSource(_ ds: FileBrowsingDomain.DataSource) {
        if !savedDataSources.contains(where: { $0.id == ds.id }) {
            savedDataSources.append(ds)
        }
        persistDataSources()
    }

    public func removeDataSource(id: UUID) {
        let removedDataSource = savedDataSources.first { $0.id == id }
        savedDataSources.removeAll { $0.id == id }
        persistDataSources()
        clearLastConnectedDataSource(id)

        if let credentialKey = removedDataSource?.credentialStorageKey {
            try? credentialStore.deleteCredential(for: credentialKey)
        }
    }

    public func loadSavedDataSources() {
        guard let data = preferences.data(forKey: Self.savedDataSourcesKey),
              let sources = try? JSONDecoder().decode([FileBrowsingDomain.DataSource].self, from: data)
        else {
            return
        }
        savedDataSources = sources
    }

    public func connectToDataSource(
        _ ds: FileBrowsingDomain.DataSource,
        isAutoReconnectAttempt: Bool = false
    ) async {
        if isAutoReconnectAttempt == false {
            cancelReconnect(clearStatusMessage: false)
        }
        activeDataSource = ds

        switch ds.connectionInfo.sourceType {
        case .local:
            await useDefaultFolder()
            return
        case .photoLibrary:
            activeDataSource = nil
            lastErrorMessage = "Photo Library source is not implemented yet."
            return
        case .webDAV, .smb:
            break
        }

        guard let adapter = adapterFactory(ds.connectionInfo.sourceType, credentialStore) else {
            activeDataSource = nil
            lastErrorMessage = "No adapter available for source type: \(ds.connectionInfo.sourceType.rawValue)"
            return
        }

        activeRemoteAdapter?.disconnect()
        do {
            try await adapter.connect(with: ds.connectionInfo)
            activeRemoteAdapter = adapter
            isLoading = true
            defer { isLoading = false }

            let remoteFiles = try await adapter.listContents(at: ds.connectionInfo.rootPath)
            files = remoteFiles
            currentRootDisplayName = ds.name
            lastErrorMessage = nil
            rememberLastConnectedDataSource(ds.id)
            reconnectStatusMessage = nil
        } catch {
            activeRemoteAdapter = nil
            activeDataSource = nil
            clearLastConnectedDataSource(ds.id)
            lastErrorMessage = "Connection failed: \(error.localizedDescription)"
            if isAutoReconnectAttempt == false {
                scheduleAutoReconnectIfNeeded(for: ds, cause: error)
            }
        }
    }

    public func connectAndSaveRemoteDataSource(
        _ dataSource: FileBrowsingDomain.DataSource,
        password: String
    ) async -> Bool {
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentialKey = dataSource.credentialStorageKey
        var previousCredential: StorageCredential?

        if let credentialKey {
            previousCredential = try? credentialStore.loadCredential(for: credentialKey)

            do {
                if let username = dataSource.connectionInfo.username, username.isEmpty == false {
                    try credentialStore.saveCredential(
                        for: credentialKey,
                        credential: StorageCredential(username: username, password: normalizedPassword)
                    )
                } else {
                    try credentialStore.deleteCredential(for: credentialKey)
                }
            } catch {
                lastErrorMessage = "Failed to save credential: \(error.localizedDescription)"
                return false
            }
        }

        await connectToDataSource(dataSource)
        guard lastErrorMessage == nil else {
            if let credentialKey {
                do {
                    if let previousCredential {
                        try credentialStore.saveCredential(for: credentialKey, credential: previousCredential)
                    } else {
                        try credentialStore.deleteCredential(for: credentialKey)
                    }
                } catch {
                    print("[FileBrowser] credential rollback failed for \(credentialKey): \(error)")
                }
            }
            return false
        }

        addDataSource(dataSource)
        return true
    }

    public func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        if let remoteAdapter = activeRemoteAdapter, let activeDataSource {
            do {
                files = try await remoteAdapter.listContents(at: activeDataSource.connectionInfo.rootPath)
                lastErrorMessage = nil
                reconnectStatusMessage = nil
            } catch {
                files = []
                lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
                scheduleAutoReconnectIfNeeded(for: activeDataSource, cause: error)
            }
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
                let playableURL: URL
                if let activeRemoteAdapter {
                    playableURL = try await activeRemoteAdapter.resolvePlayableURL(for: file)
                } else {
                    playableURL = try await localDataSource.resolvePlayableURL(for: file)
                }
                print("[FileBrowser] selected file: \(playableURL.path)")
                onPlayFile(playableURL)
            } catch {
                lastErrorMessage = "Failed to open \"\(file.name)\": \(error.localizedDescription)"
                print("[FileBrowser] selectFile failed for \(file.name): \(error)")
                return
            }
        }
    }

    public func selectLocalFolder(_ folderURL: URL) async {
        cancelReconnect(clearStatusMessage: true)
        let normalizedURL = folderURL.standardizedFileURL
        activeDataSource = nil
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil

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
        cancelReconnect(clearStatusMessage: true)
        activeDataSource = nil
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
        securityScopedRootURL?.stopAccessingSecurityScopedResource()
        securityScopedRootURL = nil
        rootURL = defaultRootURL
        currentRootDisplayName = defaultRootURL.lastPathComponent.isEmpty ? defaultRootURL.path : defaultRootURL.lastPathComponent
        clearLastConnectedDataSource()
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

    private func restoreInitialDataSource() async {
        guard let lastID = loadLastConnectedDataSourceID(),
              let dataSource = savedDataSources.first(where: { $0.id == lastID })
        else {
            await connectAndLoad()
            return
        }

        await connectToDataSource(dataSource)
        if activeDataSource == nil {
            await connectAndLoad()
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
            importQueue.async {
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func persistDataSources() {
        if let data = try? JSONEncoder().encode(savedDataSources) {
            preferences.set(data, forKey: Self.savedDataSourcesKey)
        }
    }

    private func rememberLastConnectedDataSource(_ id: UUID) {
        preferences.set(id.uuidString, forKey: Self.lastConnectedDataSourceIDKey)
    }

    private func clearLastConnectedDataSource(_ id: UUID? = nil) {
        if let id, loadLastConnectedDataSourceID() != id {
            return
        }
        preferences.removeObject(forKey: Self.lastConnectedDataSourceIDKey)
    }

    private func loadLastConnectedDataSourceID() -> UUID? {
        guard let rawValue = preferences.string(forKey: Self.lastConnectedDataSourceIDKey) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    private func scheduleAutoReconnectIfNeeded(
        for dataSource: FileBrowsingDomain.DataSource,
        cause: Error
    ) {
        guard shouldRetry(error: cause, for: dataSource.connectionInfo.sourceType) else {
            reconnectStatusMessage = nil
            return
        }

        cancelReconnect(clearStatusMessage: false)
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            for attempt in 1...reconnectPolicy.maxAttempts {
                if Task.isCancelled {
                    return
                }

                let delay = reconnectDelaySeconds(forAttempt: attempt)
                reconnectStatusMessage = "Network issue. Reconnecting to \(dataSource.name) (\(attempt)/\(reconnectPolicy.maxAttempts))..."
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled {
                    return
                }

                await connectToDataSource(dataSource, isAutoReconnectAttempt: true)
                if lastErrorMessage == nil {
                    reconnectStatusMessage = nil
                    reconnectTask = nil
                    return
                }
            }

            reconnectStatusMessage = "Reconnection stopped after \(reconnectPolicy.maxAttempts) attempts."
            reconnectTask = nil
        }
    }

    private func cancelReconnect(clearStatusMessage: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil
        if clearStatusMessage {
            reconnectStatusMessage = nil
        }
    }

    private func reconnectDelaySeconds(forAttempt attempt: Int) -> Double {
        guard attempt > 1 else {
            return reconnectPolicy.initialDelaySeconds
        }
        let exponent = Double(attempt - 1)
        let value = reconnectPolicy.initialDelaySeconds * pow(reconnectPolicy.backoffMultiplier, exponent)
        return min(value, reconnectPolicy.maxDelaySeconds)
    }

    private func shouldRetry(
        error: Error,
        for sourceType: FileBrowsingDomain.SourceType
    ) -> Bool {
        switch sourceType {
        case .webDAV:
            return isRetryableWebDAVError(error)
        case .smb:
            return false
        case .local, .photoLibrary:
            return false
        }
    }

    private func isRetryableWebDAVError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotFindHost,
                    .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
                return true
            default:
                return false
            }
        }

        if let webDAVError = error as? WebDAVError {
            switch webDAVError {
            case .requestFailed(let statusCode):
                return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
            case .invalidResponse, .malformedResponse, .notConnected:
                return true
            case .invalidConnectionInfo:
                return false
            }
        }

        return false
    }
}
