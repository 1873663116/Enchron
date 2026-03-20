import Foundation
#if canImport(AMSMB2)
import AMSMB2
#endif

public enum SMBError: LocalizedError {
    case libraryNotAvailable
    case notConnected
    case invalidConnectionInfo
    case authenticationFailed
    case networkFailed(String)
    case protocolFailed(String)
    case noShareSelected

    public var errorDescription: String? {
        switch self {
        case .libraryNotAvailable:
            return "SMB support requires the AMSMB2 library. Add it in Xcode: File → Add Package Dependencies → https://github.com/amosavian/AMSMB2"
        case .notConnected:
            return "SMB data source is not connected."
        case .invalidConnectionInfo:
            return "Invalid SMB connection information."
        case .authenticationFailed:
            return "SMB authentication failed. Check username and password."
        case .networkFailed(let reason):
            return "SMB network failed: \(reason)"
        case .protocolFailed(let reason):
            return "SMB protocol failed: \(reason)"
        case .noShareSelected:
            return "No SMB share selected. Please select a share first."
        }
    }
}

#if canImport(AMSMB2)

public final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private let credentialStore: CredentialStoring?
    private let filter = FileBrowsingDomain.FileFilter.playable
    private var smbManager: SMB2Manager?
    /// Stable DataSource ID for folder identity pass-through.
    public var ownerDataSourceID: UUID = UUID()
    public private(set) var currentConnectionInfo: FileBrowsingDomain.ConnectionInfo?
    private var connectionInfo: FileBrowsingDomain.ConnectionInfo? {
        get { currentConnectionInfo }
        set { currentConnectionInfo = newValue }
    }
    private var connectedShareName: String?

    public init(credentialStore: CredentialStoring? = nil) {
        self.credentialStore = credentialStore
    }

    /// Connect and login to the SMB server (host-only, no share yet).
    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connecting

        guard let host = info.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            connectionStatus = .failed("Invalid host")
            throw SMBError.invalidConnectionInfo
        }

        do {
            let sourceID = info.credentialSourceID
            var username = info.username ?? "guest"
            var password = ""

            if let credentialStore,
               let credential = try credentialStore.loadCredential(for: sourceID) {
                username = credential.username.isEmpty ? "guest" : credential.username
                password = credential.password
            }

            let port = info.port ?? 445
            guard let serverURL = URL(string: "smb://\(host):\(port)") else {
                throw SMBError.invalidConnectionInfo
            }
            guard let smb = SMB2Manager(
                url: serverURL,
                credential: URLCredential(
                    user: username,
                    password: password,
                    persistence: .forSession
                )
            ) else {
                throw SMBError.protocolFailed("Failed to initialize SMB client.")
            }

            smbManager = smb
            connectionInfo = info

            // If rootPath already has a share (e.g., reconnecting a saved source),
            // connect to that share immediately.
            let pathComponents = info.rootPath.split(separator: "/", omittingEmptySubsequences: true)
            if let shareName = pathComponents.first {
                try await smb.connectShare(name: String(shareName))
                connectedShareName = String(shareName)
            } else {
                _ = try await smb.listShares()
            }

            connectionStatus = .connected
        } catch {
            let mappedError = Self.classify(error)
            connectionStatus = .failed(mappedError.localizedDescription)
            throw mappedError
        }
    }

    /// List available shares on the connected server.
    /// Must be called after `connect(with:)` succeeds.
    public func listShares() async throws -> [String] {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }
        let shares = try await smb.listShares()
        // Filter out administrative/hidden shares (ending with $)
        return shares
            .map(\.name)
            .filter { !$0.hasSuffix("$") }
            .sorted()
    }

    /// Connect to a specific share after listing.
    /// Updates the connectionInfo to include the share in rootPath.
    public func selectShare(_ shareName: String) async throws {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }

        // Disconnect previous share if any
        if connectedShareName != nil {
            try? await smb.disconnectShare()
        }

        try await smb.connectShare(name: shareName)
        connectedShareName = shareName

        // Update connectionInfo with the selected share
        if let info = connectionInfo {
            connectionInfo = info.withSMBShare(shareName)
        }
    }

    public func disconnect() {
        let manager = smbManager
        Task {
            try? await manager?.disconnectShare()
        }
        smbManager = nil
        connectionInfo = nil
        connectedShareName = nil
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }
        guard connectedShareName != nil else {
            throw SMBError.noShareSelected
        }

        let smbPath = smbRelativePath(from: path)
        let items = try await smb.contentsOfDirectory(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFile? in
            let name = item[URLResourceKey.nameKey] as? String ?? ""
            let isDirectory = (item[URLResourceKey.fileResourceTypeKey] as? URLFileResourceType) == .directory
            guard !isDirectory else { return nil }

            let fullPath = Self.childPath(named: name, in: path)
            let fileURL = URL(string: "smb://placeholder\(fullPath)") ?? URL(fileURLWithPath: fullPath)
            guard filter.matches(fileURL: fileURL) else { return nil }

            let size = item[URLResourceKey.fileSizeKey] as? Int64 ?? 0
            let modified = item[URLResourceKey.contentModificationDateKey] as? Date ?? .distantPast

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
        guard let smb = smbManager, connectionInfo != nil else {
            throw SMBError.notConnected
        }
        guard connectedShareName != nil else {
            throw SMBError.noShareSelected
        }

        let smbPath = smbRelativePath(from: path)
        let items = try await smb.contentsOfDirectory(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFolder? in
            let name = item[URLResourceKey.nameKey] as? String ?? ""
            let isDirectory = (item[URLResourceKey.fileResourceTypeKey] as? URLFileResourceType) == .directory
            guard isDirectory else { return nil }
            guard name != "." && name != ".." else { return nil }

            let folderPath = Self.childPath(named: name, in: path)
            let folderURL = URL(string: "smb://placeholder\(folderPath)") ?? URL(fileURLWithPath: folderPath)

            return FileBrowsingDomain.MediaFolder(
                name: name,
                dataSourceID: self.ownerDataSourceID,
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
        return sortBy.sorted(files)
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
        let sourceID = info.credentialSourceID
        var username = info.username ?? "guest"
        var password = ""

        if let credentialStore,
           let credential = try? credentialStore.loadCredential(for: sourceID) {
            username = credential.username.isEmpty ? "guest" : credential.username
            password = credential.password
        }

        let port = info.port ?? 445
        let filePath = Self.normalizeAbsolutePath(
            file.url.path.isEmpty ? Self.childPath(named: file.name, in: info.rootPath) : file.url.path
        )

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

    private static func classify(_ error: Error) -> SMBError {
        if let smbError = error as? SMBError {
            return smbError
        }

        let nsError = error as NSError
        let reason = error.localizedDescription
        let normalizedReason = reason.lowercased()

        if nsError.domain == NSURLErrorDomain {
            return .networkFailed(reason)
        }
        if normalizedReason.contains("auth")
            || normalizedReason.contains("logon")
            || normalizedReason.contains("login")
            || normalizedReason.contains("access denied") {
            return .authenticationFailed
        }
        if normalizedReason.contains("network")
            || normalizedReason.contains("timed out")
            || normalizedReason.contains("host")
            || normalizedReason.contains("connect") {
            return .networkFailed(reason)
        }

        return .protocolFailed(reason)
    }

    /// Convert the full rootPath-based path to a path relative to the share.
    private func smbRelativePath(from path: String) -> String {
        guard let info = connectionInfo else { return Self.normalizeAbsolutePath(path) }
        return Self.shareRelativePath(for: path, rootPath: info.rootPath)
    }

    static func shareRelativePath(for path: String, rootPath: String) -> String {
        let normalizedPath = normalizeAbsolutePath(path)
        let normalizedRootPath = normalizeAbsolutePath(rootPath)
        guard let shareName = normalizedRootPath.split(separator: "/", omittingEmptySubsequences: true).first else {
            return normalizedPath
        }

        let sharePrefix = "/\(shareName)"
        guard normalizedPath == sharePrefix || normalizedPath.hasPrefix("\(sharePrefix)/") else {
            return normalizedPath
        }

        let relativePath = String(normalizedPath.dropFirst(sharePrefix.count))
        return relativePath.isEmpty ? "/" : relativePath
    }

    static func childPath(named name: String, in parentPath: String) -> String {
        let normalizedParentPath = normalizeAbsolutePath(parentPath)
        if normalizedParentPath == "/" {
            return "/\(name)"
        }
        return "\(normalizedParentPath)/\(name)"
    }

    static func normalizeAbsolutePath(_ path: String) -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.isEmpty == false else { return "/" }

        let withLeadingSlash = trimmedPath.hasPrefix("/") ? trimmedPath : "/\(trimmedPath)"
        guard withLeadingSlash.count > 1, withLeadingSlash.hasSuffix("/") else {
            return withLeadingSlash
        }
        return String(withLeadingSlash.dropLast())
    }

}

#else

// Stub implementation for platforms without AMSMB2 (e.g., Linux)
public final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    public var ownerDataSourceID: UUID = UUID()
    public private(set) var currentConnectionInfo: FileBrowsingDomain.ConnectionInfo?

    public init(credentialStore: CredentialStoring? = nil) {
        _ = credentialStore
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        throw SMBError.libraryNotAvailable
    }

    public func disconnect() {}

    public func listShares() async throws -> [String] {
        throw SMBError.libraryNotAvailable
    }

    public func selectShare(_ shareName: String) async throws {
        throw SMBError.libraryNotAvailable
    }

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
