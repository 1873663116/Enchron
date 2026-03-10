import Foundation

public enum LocalDataSourceError: Error {
    case notConnected
    case unsupportedSourceType
    case fileNotPlayable
    case itemNotReachable
}

public final class LocalDataSourceAdapter: FileProviding, DataSourceConnecting {
    private let fileManager: FileManager
    private let filter: FileBrowsingDomain.FileFilter
    private let ioQueue = DispatchQueue(label: "xrplayer.localdatasource.io", qos: .userInitiated)

    private var rootURL: URL?
    public private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    public var ownerDataSourceID: UUID = UUID()

    public init(
        fileManager: FileManager = .default,
        filter: FileBrowsingDomain.FileFilter = .playable
    ) {
        self.fileManager = fileManager
        self.filter = filter
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        guard info.sourceType == .local else {
            throw LocalDataSourceError.unsupportedSourceType
        }

        connectionStatus = .connecting
        let path = info.rootPath.isEmpty ? "/" : info.rootPath
        rootURL = URL(fileURLWithPath: path, isDirectory: true)
        connectionStatus = .connected
    }

    public func disconnect() {
        rootURL = nil
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        let baseURL = try connectedBaseURL()
        let directoryURL = URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    continuation.resume(returning: try loadMediaFiles(in: directoryURL))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        let baseURL = try connectedBaseURL()
        let directoryURL = URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    let contents = try fileManager.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    )
                    let folders = contents.compactMap { url -> FileBrowsingDomain.MediaFolder? in
                        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                        guard values?.isDirectory == true else { return nil }
                        return FileBrowsingDomain.MediaFolder(
                            name: url.lastPathComponent,
                            dataSourceID: self.ownerDataSourceID,
                            path: url.path,
                            url: url
                        )
                    }
                    continuation.resume(returning: folders)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        let reachable = try item.url.checkResourceIsReachable()
        guard reachable else { throw LocalDataSourceError.itemNotReachable }
        return item.url
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    let files = try loadMediaFiles(in: folder.url)
                    continuation.resume(returning: sort(files: files, by: sortBy))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
        guard filter.matches(fileURL: file.url) else {
            throw LocalDataSourceError.fileNotPlayable
        }
        return try await resolveURL(for: file)
    }

    private func connectedBaseURL() throws -> URL {
        guard case .connected = connectionStatus, let rootURL else {
            throw LocalDataSourceError.notConnected
        }
        return rootURL
    }

    private func loadMediaFiles(in directoryURL: URL) throws -> [FileBrowsingDomain.MediaFile] {
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { return nil }
            guard filter.matches(fileURL: url) else { return nil }

            return FileBrowsingDomain.MediaFile(
                name: url.lastPathComponent,
                sizeInBytes: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate ?? .distantPast,
                fileExtension: url.pathExtension,
                url: url
            )
        }
    }

    private func sort(
        files: [FileBrowsingDomain.MediaFile],
        by criteria: FileBrowsingDomain.SortCriteria
    ) -> [FileBrowsingDomain.MediaFile] {
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
            return sorted
        case .descending:
            return sorted.reversed()
        }
    }
}
