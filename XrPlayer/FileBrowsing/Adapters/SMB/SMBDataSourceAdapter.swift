import Foundation

#if canImport(AMSMB2)
import AMSMB2
#endif

public enum SMBError: LocalizedError {
    case libraryNotAvailable
    case invalidConnectionInfo
    case notConnected
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .libraryNotAvailable:
            return "SMB support requires the AMSMB2 library. Add it in Xcode: File -> Add Package Dependencies -> https://github.com/amosavian/AMSMB2"
        case .invalidConnectionInfo:
            return "Invalid SMB connection information. Use root path format: /share or /share/subfolder."
        case .notConnected:
            return "SMB data source is not connected."
        case .connectionFailed(let reason):
            return "SMB connection failed: \(reason)"
        }
    }
}

public final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

#if canImport(AMSMB2)
    private var manager: SMB2Manager?
    private var host: String?
    private var port: Int?
    private var shareName: String?
    private var rootDirectoryWithinShare: String = "/"
    private var username: String?
    private var password: String?
#endif

    private let credentialStore: CredentialStoring?
    private let filter = FileBrowsingDomain.FileFilter.playable

    public init(credentialStore: CredentialStoring? = nil) {
        self.credentialStore = credentialStore
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
#if canImport(AMSMB2)
        guard info.sourceType == .smb,
              let host = normalizedHost(info.host),
              let serverURL = makeServerURL(host: host, port: info.port)
        else {
            throw SMBError.invalidConnectionInfo
        }

        let shareAndPath = parseShareAndPath(info.rootPath)
        guard let shareAndPath else {
            throw SMBError.invalidConnectionInfo
        }

        connectionStatus = .connecting
        do {
            let auth = try resolveCredential(for: info)
            let credential = URLCredential(
                user: auth.username,
                password: auth.password,
                persistence: .forSession
            )
            guard let manager = SMB2Manager(url: serverURL, credential: credential) else {
                throw SMBError.connectionFailed("Unable to initialize SMB manager.")
            }

            try await manager.connectShare(name: shareAndPath.share)
            _ = try await manager.contentsOfDirectory(atPath: shareAndPath.pathInShare)

            self.manager = manager
            self.host = host
            self.port = info.port
            self.shareName = shareAndPath.share
            self.rootDirectoryWithinShare = shareAndPath.pathInShare
            self.username = auth.username
            self.password = auth.password
            connectionStatus = .connected
        } catch {
            self.manager = nil
            connectionStatus = .failed(error.localizedDescription)
            throw SMBError.connectionFailed(error.localizedDescription)
        }
#else
        _ = info
        throw SMBError.libraryNotAvailable
#endif
    }

    public func disconnect() {
#if canImport(AMSMB2)
        if let manager {
            Task {
                try? await manager.disconnectShare()
            }
        }
        manager = nil
        host = nil
        port = nil
        shareName = nil
        rootDirectoryWithinShare = "/"
        username = nil
        password = nil
#endif
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
#if canImport(AMSMB2)
        guard let manager, let shareName else {
            throw SMBError.notConnected
        }

        let pathInShare = pathWithinShare(for: path, shareName: shareName)
        let entries = try await manager.contentsOfDirectory(atPath: pathInShare)
        return entries.compactMap { entry in
            guard let name = entry[.nameKey] as? String else { return nil }
            if name == "." || name == ".." { return nil }
            if (entry[.fileResourceTypeKey] as? URLFileResourceType) == .directory {
                return nil
            }

            let resourcePath = (entry[.pathKey] as? String) ?? pathInShare
            let fullPath = appendPath(name: name, to: resourcePath)
            let fileURL = makeItemURL(shareName: shareName, pathInShare: fullPath, includeCredentials: false)
            guard let fileURL, filter.matches(fileURL: fileURL) else {
                return nil
            }

            let size = (entry[.fileSizeKey] as? Int64) ?? Int64(entry[.fileSizeKey] as? Int ?? 0)
            let modifiedAt = (entry[.contentModificationDateKey] as? Date) ?? .distantPast
            return FileBrowsingDomain.MediaFile(
                name: name,
                sizeInBytes: size,
                modifiedAt: modifiedAt,
                fileExtension: fileURL.pathExtension,
                url: fileURL
            )
        }
#else
        _ = path
        throw SMBError.libraryNotAvailable
#endif
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
#if canImport(AMSMB2)
        let files = try await listContents(at: folder.path)
        return sort(files: files, by: sortBy)
#else
        _ = folder
        _ = sortBy
        throw SMBError.libraryNotAvailable
#endif
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
#if canImport(AMSMB2)
        return item.url
#else
        _ = item
        throw SMBError.libraryNotAvailable
#endif
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
#if canImport(AMSMB2)
        guard let shareName else {
            throw SMBError.notConnected
        }
        let relativePath = normalizedPath(file.url.path)
        if let resolved = makeItemURL(
            shareName: shareName,
            pathInShare: relativePath,
            includeCredentials: true
        ) {
            return resolved
        }
        return file.url
#else
        _ = file
        throw SMBError.libraryNotAvailable
#endif
    }

#if canImport(AMSMB2)
    private func resolveCredential(
        for info: FileBrowsingDomain.ConnectionInfo
    ) throws -> (username: String, password: String) {
        var finalUsername = info.username?.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalPassword = ""

        if let credentialStore, let key = info.credentialStorageKey,
           let credential = try credentialStore.loadCredential(for: key) {
            finalUsername = credential.username
            finalPassword = credential.password
        }

        let username = (finalUsername?.isEmpty == false) ? finalUsername! : "guest"
        return (username, finalPassword)
    }

    private func parseShareAndPath(_ rootPath: String) -> (share: String, pathInShare: String)? {
        let normalized = normalizedPath(rootPath)
        let components = normalized
            .split(separator: "/")
            .map(String.init)
        guard let share = components.first, share.isEmpty == false else {
            return nil
        }

        let pathComponents = components.dropFirst()
        if pathComponents.isEmpty {
            return (share, "/")
        }
        return (share, "/" + pathComponents.joined(separator: "/"))
    }

    private func makeServerURL(host: String, port: Int?) -> URL? {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = host
        if let port {
            components.port = port
        }
        return components.url
    }

    private func makeItemURL(
        shareName: String,
        pathInShare: String,
        includeCredentials: Bool
    ) -> URL? {
        guard let host else { return nil }
        var components = URLComponents()
        components.scheme = "smb"
        components.host = host
        components.port = port
        components.path = "/\(shareName)\(normalizedPath(pathInShare))"

        if includeCredentials, let username, username.isEmpty == false {
            components.user = username
            if let password, password.isEmpty == false {
                components.password = password
            }
        }
        return components.url
    }

    private func pathWithinShare(
        for requestedPath: String,
        shareName: String
    ) -> String {
        let normalized = normalizedPath(requestedPath)
        let sharePrefix = "/\(shareName)"

        if normalized == "/" {
            return rootDirectoryWithinShare
        }
        if normalized == sharePrefix {
            return "/"
        }
        if normalized.hasPrefix(sharePrefix + "/") {
            let stripped = String(normalized.dropFirst(sharePrefix.count))
            return normalizedPath(stripped)
        }
        return normalized
    }

    private func appendPath(name: String, to basePath: String) -> String {
        let base = normalizedPath(basePath)
        if base == "/" {
            return "/" + name
        }
        if base.hasSuffix("/") {
            return base + name
        }
        return base + "/" + name
    }

    private func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "/" }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return "/" + trimmed
    }

    private func normalizedHost(_ host: String?) -> String? {
        guard let host else { return nil }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return trimmed
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
#endif
}
