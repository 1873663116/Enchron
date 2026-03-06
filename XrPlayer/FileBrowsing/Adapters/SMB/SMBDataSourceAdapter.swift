import Foundation

public enum SMBError: LocalizedError {
    case libraryNotAvailable

    public var errorDescription: String? {
        "SMB support requires the AMSMB2 library. Add it in Xcode: File → Add Package Dependencies → https://github.com/amosavian/AMSMB2"
    }
}

public final class SMBDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

    public init(credentialStore: CredentialStoring? = nil) {
        _ = credentialStore
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        _ = info
        throw SMBError.libraryNotAvailable
    }

    public func disconnect() {}

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        _ = path
        throw SMBError.libraryNotAvailable
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        _ = folder
        _ = sortBy
        throw SMBError.libraryNotAvailable
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        _ = item
        throw SMBError.libraryNotAvailable
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
        _ = file
        throw SMBError.libraryNotAvailable
    }
}
