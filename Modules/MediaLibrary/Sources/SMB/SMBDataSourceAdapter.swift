import AMSMB2
import Foundation
import MediaSource

public nonisolated enum SMBError: LocalizedError, Sendable {
    case notConnected
    case invalidConnectionInfo
    case authenticationFailed
    case networkFailed(String)
    case protocolFailed(String)
    case streamingFailed(String)
    case noShareSelected

    public var errorDescription: String? {
        switch self {
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
        case .streamingFailed(let reason):
            return "SMB playback stream failed: \(reason)"
        case .noShareSelected:
            return "No SMB share selected. Please select a share first."
        }
    }
}

nonisolated final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding, @unchecked Sendable {
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

    init(credentialStore: CredentialStoring? = nil) {
        self.credentialStore = credentialStore
    }

    deinit {
        disconnect()
    }

    /// Connect and authenticate to the server. Shares remain folders at root.
    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connecting

        do {
            let smb = try makeManager(for: info)

            _ = try await smb.listShares()

            smbManager = smb
            connectionInfo = info
            connectionStatus = .connected
        } catch {
            smbManager = nil
            connectionInfo = nil
            connectedShareName = nil
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

    /// Connect to a share while preserving the server as the source root.
    public func selectShare(_ shareName: String) async throws {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }

        if connectedShareName != nil {
            try? await smb.disconnectShare()
        }

        try await smb.connectShare(name: shareName)
        connectedShareName = shareName

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
        try await listFiles(at: path, matching: filter)
    }

    public func listSubtitleFiles(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        try await listFiles(at: path, matching: .externalSubtitles)
    }

    private func listFiles(
        at path: String,
        matching fileFilter: FileBrowsingDomain.FileFilter
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        guard let smb = smbManager else {
            throw SMBError.notConnected
        }
        guard Self.normalizeAbsolutePath(path) != "/" else { return [] }

        let smbPath = try await prepareShare(for: path)
        let items = try await smb.contentsOfDirectory(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFile? in
            let name = item[URLResourceKey.nameKey] as? String ?? ""
            let isDirectory = (item[URLResourceKey.fileResourceTypeKey] as? URLFileResourceType) == .directory
            guard !isDirectory else { return nil }

            let fullPath = Self.childPath(named: name, in: path)
            let fileURL = URL(string: "smb://placeholder\(fullPath)") ?? URL(fileURLWithPath: fullPath)
            guard fileFilter.matches(fileURL: fileURL) else { return nil }

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
        if Self.normalizeAbsolutePath(path) == "/" {
            return try await listShares().map { shareName in
                let folderPath = "/\(shareName)"
                return FileBrowsingDomain.MediaFolder(
                    name: shareName,
                    dataSourceID: ownerDataSourceID,
                    path: folderPath,
                    url: URL(string: "smb://placeholder\(folderPath)")
                        ?? URL(fileURLWithPath: folderPath)
                )
            }
        }

        let smbPath = try await prepareShare(for: path)
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

    public func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> MediaByteStreamHandle {
        guard smbManager != nil, let info = connectionInfo else {
            throw SMBError.notConnected
        }
        guard let (shareName, remotePath) = Self.shareAndRelativePath(for: file.url.path) else {
            throw SMBError.noShareSelected
        }
        guard file.sizeInBytes > 0 else {
            throw SMBError.streamingFailed("The server did not report the remote file size.")
        }
        let playbackManager = try makeManager(for: info)
        do {
            try await playbackManager.connectShare(name: shareName)
            let source = SMBByteRangeSource(
                manager: playbackManager,
                path: remotePath,
                contentLength: file.sizeInBytes
            )
            return try await MediaByteStreamEndpoint.shared.resolve(
                source,
                filename: file.name,
                onTermination: {
                    try? await playbackManager.disconnectShare()
                }
            )
        } catch {
            Task { try? await playbackManager.disconnectShare() }
            throw SMBError.streamingFailed(error.localizedDescription)
        }
    }

    private func makeManager(
        for info: FileBrowsingDomain.ConnectionInfo
    ) throws -> SMB2Manager {
        guard let host = info.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              host.isEmpty == false else {
            throw SMBError.invalidConnectionInfo
        }

        var username = info.username ?? "guest"
        var password = ""
        if let credentialStore,
           let credential = try credentialStore.loadCredential(for: info) {
            username = credential.username.isEmpty ? "guest" : credential.username
            password = credential.password
        }

        guard let serverURL = URL(string: "smb://\(host):\(info.port ?? 445)") else {
            throw SMBError.invalidConnectionInfo
        }
        guard let manager = SMB2Manager(
            url: serverURL,
            credential: URLCredential(
                user: username,
                password: password,
                persistence: .forSession
            )
        ) else {
            throw SMBError.protocolFailed("Failed to initialize SMB client.")
        }
        return manager
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

    private func prepareShare(for path: String) async throws -> String {
        guard let (shareName, relativePath) = Self.shareAndRelativePath(for: path) else {
            throw SMBError.noShareSelected
        }
        if connectedShareName != shareName {
            try await selectShare(shareName)
        }
        return relativePath
    }

    static func shareAndRelativePath(for path: String) -> (share: String, relativePath: String)? {
        let components = normalizeAbsolutePath(path)
            .split(separator: "/", omittingEmptySubsequences: true)
        guard let share = components.first else { return nil }
        let remainder = components.dropFirst().joined(separator: "/")
        return (String(share), remainder.isEmpty ? "/" : "/\(remainder)")
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

private nonisolated final class SMBByteRangeSource: MediaByteSource, @unchecked Sendable {
    let totalLength: Int64?
    let seekability = MediaByteSourceSeekability.randomAccess
    let liveness = MediaByteSourceLiveness.finite
    let suggestedBufferDepth = MediaByteBufferDepth.bytes(1_024 * 1_024)
    private let manager: SMB2Manager
    private let path: String

    init(manager: SMB2Manager, path: String, contentLength: Int64) {
        self.manager = manager
        self.path = path
        totalLength = contentLength
    }

    func read(in range: Range<Int64>) async throws -> Data {
        try await manager.contents(
            atPath: path,
            range: UInt64(range.lowerBound)..<UInt64(range.upperBound)
        )
    }
}
