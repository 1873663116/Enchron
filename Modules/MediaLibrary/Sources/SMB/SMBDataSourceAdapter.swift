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
    private var serverConnection: SMBServerConnection?
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
            let connection = try SMBConnectionPool.shared.connection(for: info) {
                try self.makeManager(for: info)
            }
            _ = try await connection.listShares()

            serverConnection = connection
            connectionInfo = info
            connectionStatus = .connected
        } catch {
            serverConnection = nil
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
        guard let connection = serverConnection else {
            throw SMBError.notConnected
        }
        let shares = try await connection.listShares()
        // Filter out administrative/hidden shares (ending with $)
        return shares
            .map(\.name)
            .filter { !$0.hasSuffix("$") }
            .sorted()
    }

    /// Connect to a share while preserving the server as the source root.
    public func selectShare(_ shareName: String) async throws {
        guard let connection = serverConnection else {
            throw SMBError.notConnected
        }
        try await connection.connectShare(name: shareName)
        connectedShareName = shareName

    }

    public func disconnect() {
        serverConnection = nil
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
        guard let connection = serverConnection else {
            throw SMBError.notConnected
        }
        guard Self.normalizeAbsolutePath(path) != "/" else { return [] }

        let smbPath = try await prepareShare(for: path)
        let items = try await connection.directoryItems(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFile? in
            let name = item.name
            guard item.isDirectory == false else { return nil }

            let fullPath = Self.childPath(named: name, in: path)
            let fileURL = URL(string: "smb://placeholder\(fullPath)") ?? URL(fileURLWithPath: fullPath)
            guard fileFilter.matches(fileURL: fileURL) else { return nil }

            return FileBrowsingDomain.MediaFile(
                name: name,
                sizeInBytes: item.sizeInBytes,
                modifiedAt: item.modifiedAt,
                fileExtension: (name as NSString).pathExtension,
                url: fileURL
            )
        }
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        guard let connection = serverConnection, connectionInfo != nil else {
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
        let items = try await connection.directoryItems(atPath: smbPath)

        return items.compactMap { item -> FileBrowsingDomain.MediaFolder? in
            let name = item.name
            guard item.isDirectory else { return nil }
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
    ) async throws -> ResolvedMediaSource {
        guard let connection = serverConnection, connectionInfo != nil else {
            throw SMBError.notConnected
        }
        guard let (shareName, remotePath) = Self.shareAndRelativePath(for: file.url.path) else {
            throw SMBError.noShareSelected
        }
        do {
            try await connection.connectShare(name: shareName)
            let source = SMBByteRangeSource(
                connection: connection,
                shareName: shareName,
                path: remotePath,
                reportedContentLength: file.sizeInBytes
            )
            let handle = try await MediaByteStreamServer.shared.register(
                source: source,
                filename: file.name
            )
            return ResolvedMediaSource(byteStreamHandle: handle)
        } catch {
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
        // `connectShare` verifies the pooled connection and reconnects when needed.
        try await selectShare(shareName)
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

private nonisolated final class SMBByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes
    private let connection: SMBServerConnection
    private let shareName: String
    private let path: String
    private let lock = NSLock()
    private var currentContentLength: Int64?

    init(
        connection: SMBServerConnection,
        shareName: String,
        path: String,
        reportedContentLength: Int64
    ) {
        self.connection = connection
        self.shareName = shareName
        self.path = path
        currentContentLength = nil
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: reportedContentLength > 0 ? reportedContentLength : nil,
            supportsSeeking: true,
            isLive: false,
            preferredBufferDepth: .automatic
        )
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let length: Int64
        if let cached = lock.withLock({ currentContentLength }) {
            length = cached
        } else {
            let size = try await connection.contentLength(
                shareName: shareName,
                path: path
            )
            guard size >= 0 else {
                throw SMBError.streamingFailed("The server did not report the current file size.")
            }
            lock.withLock { currentContentLength = size }
            length = size
        }
        let upper = min(range.upperBound, length)
        guard range.lowerBound < upper else {
            return MediaByteRangeRead(data: Data(), contentLength: length, supportsSeeking: true)
        }
        let data = try await connection.contents(
            shareName: shareName,
            atPath: path,
            range: UInt64(range.lowerBound)..<UInt64(upper)
        )
        return MediaByteRangeRead(
            data: data,
            contentLength: length,
            supportsSeeking: true
        )
    }
}

private nonisolated final class SMBConnectionPool: @unchecked Sendable {
    static let shared = SMBConnectionPool()

    private let lock = NSLock()
    private var connections: [String: SMBServerConnection] = [:]

    func connection(
        for info: FileBrowsingDomain.ConnectionInfo,
        makeManager: () throws -> SMB2Manager
    ) throws -> SMBServerConnection {
        let key = "\((info.host ?? "").lowercased()):\(info.port ?? 445)"
        if let existing = lock.withLock({ connections[key] }) { return existing }
        let connection = SMBServerConnection(manager: try makeManager())
        return lock.withLock {
            if let existing = connections[key] { return existing }
            connections[key] = connection
            return connection
        }
    }
}

private actor SMBServerConnection {
    struct DirectoryItem: Sendable {
        let name: String
        let isDirectory: Bool
        let sizeInBytes: Int64
        let modifiedAt: Date
    }

    private let manager: SMB2Manager

    init(manager: SMB2Manager) {
        self.manager = manager
    }

    func listShares() async throws -> [(name: String, comment: String)] {
        try await manager.listShares()
    }

    func connectShare(name: String) async throws {
        try await manager.connectShare(name: name)
    }

    func directoryItems(atPath path: String) async throws -> [DirectoryItem] {
        try await manager.contentsOfDirectory(atPath: path).map { item in
            DirectoryItem(
                name: item[.nameKey] as? String ?? "",
                isDirectory: (item[.fileResourceTypeKey] as? URLFileResourceType) == .directory,
                sizeInBytes: item[.fileSizeKey] as? Int64
                    ?? (item[.fileSizeKey] as? Int).map(Int64.init)
                    ?? 0,
                modifiedAt: item[.contentModificationDateKey] as? Date ?? .distantPast
            )
        }
    }

    func contentLength(
        shareName: String,
        path: String
    ) async throws -> Int64 {
        try await manager.connectShare(name: shareName)
        let attributes = try await manager.attributesOfItem(atPath: path)
        return attributes[.fileSizeKey] as? Int64
            ?? (attributes[.fileSizeKey] as? Int).map(Int64.init)
            ?? -1
    }

    func contents(
        shareName: String,
        atPath path: String,
        range: Range<UInt64>
    ) async throws -> Data {
        try await manager.connectShare(name: shareName)
        return try await manager.contents(atPath: path, range: range)
    }
}
