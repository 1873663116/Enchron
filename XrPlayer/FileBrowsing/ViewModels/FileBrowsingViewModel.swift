import Foundation
import Observation

@MainActor
@Observable
public final class FileBrowsingViewModel {
    public var files: [FileBrowsingDomain.MediaFile] = []
    public var isLoading: Bool = false
    public var lastErrorMessage: String?
    public private(set) var currentRootDisplayName: String = "Documents"

    public var savedDataSources: [FileBrowsingDomain.DataSource] = []
    public var activeDataSource: FileBrowsingDomain.DataSource?

    private let localDataSource: LocalDataSourceAdapter
    private let fileManager: FileManager
    private let credentialStore: CredentialStoring
    private static let savedDataSourcesKey = "xrplayer.savedDataSources"
    private let importQueue = DispatchQueue(label: "xrplayer.fileimport.io", qos: .utility)
    private let onPlayFile: @MainActor (URL) -> Void
    private let defaultRootURL: URL
    private var rootURL: URL
    private var securityScopedRootURL: URL?
    private var activeRemoteAdapter: (any DataSourceConnecting & FileProviding)?

    public init(
        localDataSource: LocalDataSourceAdapter,
        fileManager: FileManager = .default,
        credentialStore: CredentialStoring = KeychainStore(),
        onPlayFile: @escaping @MainActor (URL) -> Void
    ) {
        self.localDataSource = localDataSource
        self.fileManager = fileManager
        self.credentialStore = credentialStore
        self.onPlayFile = onPlayFile
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.defaultRootURL = documentsURL
        self.rootURL = documentsURL
        self.currentRootDisplayName = documentsURL.lastPathComponent.isEmpty ? documentsURL.path : documentsURL.lastPathComponent

        Task { [weak self] in
            await self?.connectAndLoad()
        }

        loadSavedDataSources()
    }

    public func addDataSource(_ ds: FileBrowsingDomain.DataSource) {
        if !savedDataSources.contains(where: { $0.id == ds.id }) {
            savedDataSources.append(ds)
        }
        persistDataSources()
    }

    public func removeDataSource(id: UUID) {
        savedDataSources.removeAll { $0.id == id }
        persistDataSources()
    }

    public func loadSavedDataSources() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedDataSourcesKey),
              let sources = try? JSONDecoder().decode([FileBrowsingDomain.DataSource].self, from: data)
        else {
            return
        }
        savedDataSources = sources
    }

    public func connectToDataSource(_ ds: FileBrowsingDomain.DataSource) async {
        activeDataSource = ds

        let adapter: any DataSourceConnecting & FileProviding
        switch ds.connectionInfo.sourceType {
        case .webDAV:
            adapter = WebDAVDataSourceAdapter(credentialStore: credentialStore)
        case .smb:
            adapter = SMBDataSourceAdapter(credentialStore: credentialStore)
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
            isLoading = true
            defer { isLoading = false }

            let remoteFiles = try await adapter.listContents(at: ds.connectionInfo.rootPath)
            files = remoteFiles
            currentRootDisplayName = ds.name
            lastErrorMessage = nil
        } catch {
            activeRemoteAdapter = nil
            activeDataSource = nil
            lastErrorMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    public func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        if let remoteAdapter = activeRemoteAdapter, let activeDataSource {
            do {
                files = try await remoteAdapter.listContents(at: activeDataSource.connectionInfo.rootPath)
                lastErrorMessage = nil
            } catch {
                files = []
                lastErrorMessage = "Failed to load files: \(error.localizedDescription)"
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
        activeDataSource = nil
        activeRemoteAdapter?.disconnect()
        activeRemoteAdapter = nil
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
        if let data = try? JSONEncoder().encode(savedDataSources) {
            UserDefaults.standard.set(data, forKey: Self.savedDataSourcesKey)
        }
    }
}
