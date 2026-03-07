import Foundation
#if canImport(AMSMB2)
import AMSMB2
#endif

public enum SMBError: LocalizedError {
    case libraryNotAvailable
    case notConnected
    case invalidConnectionInfo
    case connectionFailed(String)
    case authenticationFailed

    public var errorDescription: String? {
        switch self {
        case .libraryNotAvailable:
            return "SMB support requires the AMSMB2 library. Add it in Xcode: File → Add Package Dependencies → https://github.com/amosavian/AMSMB2"
        case .notConnected:
            return "SMB data source is not connected."
        case .invalidConnectionInfo:
            return "Invalid SMB connection information."
        case .connectionFailed(let reason):
            return "SMB connection failed: \(reason)"
        case .authenticationFailed:
            return "SMB authentication failed. Check username and password."
        }
    }
}

#if canImport(AMSMB2)

public final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private let credentialStore: CredentialStoring?
    private let filter = FileBrowsingDomain.FileFilter.playable
    private var smbManager: AMSMB2?
    private var connectionInfo: FileBrowsingDomain.ConnectionInfo?

    public init(credentialStore: CredentialStoring? = nil) {
        self.credentialStore = credentialStore
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connecting

        guard let host = info.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            connectionStatus = .failed("Invalid host")
            throw SMBError.invalidConnectionInfo
        }

        do {
            let sourceID = credentialSourceID(info: info)
            var username = info.username ?? "guest"
            var password = ""

            if let credentialStore,
               let credential = try credentialStore.loadCredential(for: sourceID) {
                username = credential.username.isEmpty ? "guest" : credential.username
                password = credential.password
            }

            let port = info.port ?? 445
            let serverURL = URL(string: "smb://\(host):\(port)")!

            let smb = AMSMB2(url: serverURL, credential: URLCredential(
                user: username,
                password: password,
                persistence: .forSession
            ))!

            try await smb.connectAndLogin()

            // Extract share name from rootPath (first path component)
            let rootPath = info.rootPath
            let pathComponents = rootPath.split(separator: "/", omittingEmptySubsequences: true)
            guard let shareName = pathComponents.first else {
                throw SMBError.invalidConnectionInfo
            }

            try await smb.connectShare(name: String(shareName))

            smbManager = smb
            connectionInfo = info
            connectionStatus = .connected
        } catch let error as SMBError {
            connectionStatus = .failed(error.localizedDescription)
            throw error
        } catch {
            connectionStatus = .failed(error.localizedDescription)
            throw SMBError.connectionFailed(error.localizedDescription)
        }
    }

    public func disconnect() {
        smbManager?.disconnectShare()
        smbManager = nil
        connectionInfo = nil
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }

        let smbPath = smbRelativePath(from: path)
        let items = try await smb.contentsOfDirectory(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFile? in
            let name = item[.nameKey] as? String ?? ""
            let isDirectory = (item[.fileResourceTypeKey] as? URLFileResourceType) == .directory
            guard !isDirectory else { return nil }

            let fileURL = URL(string: "smb://placeholder/\(name)") ?? URL(fileURLWithPath: "/\(name)")
            guard filter.matches(fileURL: fileURL) else { return nil }

            let size = item[.fileSizeKey] as? Int64 ?? 0
            let modified = item[.contentModificationDateKey] as? Date ?? .distantPast

            return FileBrowsingDomain.MediaFile(
                name: name,
                sizeInBytes: size,
                modifiedAt: modified,
                fileExtension: (name as NSString).pathExtension,
                url: fileURL
            )
        }
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }

        let smbPath = smbRelativePath(from: path)
        let items = try await smb.contentsOfDirectory(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFolder? in
            let name = item[.nameKey] as? String ?? ""
            let isDirectory = (item[.fileResourceTypeKey] as? URLFileResourceType) == .directory
            guard isDirectory else { return nil }
            guard name != "." && name != ".." else { return nil }

            let folderPath = smbPath.hasSuffix("/") ? "\(smbPath)\(name)" : "\(smbPath)/\(name)"
            let folderURL = URL(string: "smb://placeholder\(folderPath)") ?? URL(fileURLWithPath: folderPath)

            return FileBrowsingDomain.MediaFolder(
                name: name,
                dataSourceID: UUID(),
                path: folderPath,
                url: folderURL
            )
        }
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        let files = try await listContents(at: folder.path)
        return sort(files: files, by: sortBy)
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        item.url
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
        guard let info = connectionInfo,
              let host = info.host else {
            return file.url
        }

        // Construct smb:// URL with credentials for mpv playback
        let sourceID = credentialSourceID(info: info)
        var username = info.username ?? "guest"
        var password = ""

        if let credentialStore,
           let credential = try? credentialStore.loadCredential(for: sourceID) {
            username = credential.username.isEmpty ? "guest" : credential.username
            password = credential.password
        }

        let port = info.port ?? 445
        let rootPath = info.rootPath.hasPrefix("/") ? info.rootPath : "/\(info.rootPath)"
        let filePath = "\(rootPath)/\(file.name)"

        var components = URLComponents()
        components.scheme = "smb"
        components.host = host
        components.port = port
        components.user = username
        if !password.isEmpty {
            components.password = password
        }
        components.path = filePath

        return components.url ?? file.url
    }

    private func credentialSourceID(info: FileBrowsingDomain.ConnectionInfo) -> String {
        let type = info.sourceType.rawValue
        let host = info.host ?? ""
        let port = info.port ?? 0
        let path = info.rootPath
        return "\(type):\(host):\(port):\(path)"
    }

    /// Convert the full rootPath-based path to a path relative to the share.
    /// e.g., rootPath="/share/videos", path="/share/videos/subfolder" → "videos/subfolder"
    private func smbRelativePath(from path: String) -> String {
        guard let info = connectionInfo else { return path }
        let components = info.rootPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else { return "/" }

        // Drop the share name (first component), keep the rest
        let subPath = components.dropFirst().joined(separator: "/")
        if path == info.rootPath {
            return subPath.isEmpty ? "/" : "/\(subPath)"
        }

        // For navigated paths, strip rootPath prefix and use as-is
        return path.hasPrefix("/") ? path : "/\(path)"
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
        return criteria.order == .ascending ? sorted : sorted.reversed()
    }
}

#else

// Stub implementation for platforms without AMSMB2 (e.g., Linux)
public final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

    public init(credentialStore: CredentialStoring? = nil) {
        _ = credentialStore
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        throw SMBError.libraryNotAvailable
    }

    public func disconnect() {}

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        throw SMBError.libraryNotAvailable
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        throw SMBError.libraryNotAvailable
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        throw SMBError.libraryNotAvailable
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        throw SMBError.libraryNotAvailable
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
        throw SMBError.libraryNotAvailable
    }
}

#endif
