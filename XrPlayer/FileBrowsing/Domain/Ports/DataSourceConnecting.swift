import Foundation

public nonisolated protocol DataSourceConnecting {
    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws
    func disconnect()

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile]
    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder]
    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL

    var connectionStatus: FileBrowsingDomain.ConnectionStatus { get }
}
