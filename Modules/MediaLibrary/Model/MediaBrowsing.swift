import Foundation


nonisolated extension FileBrowsingDomain {
    public struct MediaFile: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let sizeInBytes: Int64
        public let modifiedAt: Date
        public let fileExtension: String
        public let url: URL

        public init(
            id: UUID = UUID(),
            name: String,
            sizeInBytes: Int64,
            modifiedAt: Date,
            fileExtension: String,
            url: URL
        ) {
            self.id = id
            self.name = name
            self.sizeInBytes = sizeInBytes
            self.modifiedAt = modifiedAt
            self.fileExtension = fileExtension.lowercased()
            self.url = url
        }
    }
}


nonisolated extension FileBrowsingDomain {
    public struct MediaFolder: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let dataSourceID: UUID
        public let path: String
        public let url: URL

        public init(id: String? = nil, name: String, dataSourceID: UUID, path: String, url: URL) {
            self.id = id ?? Self.identity(for: dataSourceID, path: path)
            self.name = name
            self.dataSourceID = dataSourceID
            self.path = path
            self.url = url
        }

        private static func identity(for dataSourceID: UUID, path: String) -> String {
            let normalizedPath = path.isEmpty ? "/" : path
            return "\(dataSourceID.uuidString.lowercased()):\(normalizedPath)"
        }
    }
}


nonisolated extension FileBrowsingDomain {
    public struct FileFilter: Sendable, Equatable {
        public let allowedExtensions: Set<String>

        public init(allowedExtensions: Set<String>) {
            self.allowedExtensions = Set(allowedExtensions.map { $0.lowercased() })
        }

        public func matches(fileURL: URL) -> Bool {
            allowedExtensions.contains(fileURL.pathExtension.lowercased())
        }

        public static let playable = FileFilter(
            allowedExtensions: [
                "mp4", "mkv", "avi", "mov", "m4v", "webm", "ts", "m2ts", "flv"
            ]
        )
    }
}


nonisolated extension FileBrowsingDomain {
    public struct SortCriteria: Sendable, Equatable {
        public enum Key: Sendable {
            case name
            case modifiedDate
            case size
        }

        public enum Order: Sendable {
            case ascending
            case descending
        }

        public let key: Key
        public let order: Order

        public init(key: Key, order: Order) {
            self.key = key
            self.order = order
        }

        public func sorted(_ files: [FileBrowsingDomain.MediaFile]) -> [FileBrowsingDomain.MediaFile] {
            let sorted: [FileBrowsingDomain.MediaFile]

            switch key {
            case .name:
                sorted = files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .modifiedDate:
                sorted = files.sorted { $0.modifiedAt < $1.modifiedAt }
            case .size:
                sorted = files.sorted { $0.sizeInBytes < $1.sizeInBytes }
            }

            switch order {
            case .ascending:
                return sorted
            case .descending:
                return Array(sorted.reversed())
            }
        }

        public static let nameAscending = SortCriteria(key: .name, order: .ascending)
    }
}


public nonisolated final class FilePlaybackSourceLease: @unchecked Sendable {
    private let lock = NSLock()
    private var releaseAction: (@Sendable () -> Void)?

    public init(release: @escaping @Sendable () -> Void) {
        releaseAction = release
    }

    public func release() {
        let action = lock.withLock {
            let action = releaseAction
            releaseAction = nil
            return action
        }
        action?()
    }

    deinit {
        release()
    }
}

public nonisolated struct FilePlaybackSource: @unchecked Sendable {
    public let url: URL
    public let lease: FilePlaybackSourceLease?

    public init(url: URL, lease: FilePlaybackSourceLease? = nil) {
        self.url = url
        self.lease = lease
    }
}

public nonisolated protocol FileProviding {
    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile]

    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> FilePlaybackSource
}


public nonisolated protocol DataSourceConnecting {
    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws
    func disconnect()

    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile]
    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder]
    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL

    var connectionStatus: FileBrowsingDomain.ConnectionStatus { get }
}


/// The local file source the browsing view-model depends on: a `FileProviding`
/// + `DataSourceConnecting` adapter that also exposes a settable owning data
/// source identifier.
///
/// Both the production `LocalDataSourceAdapter` and the `FakeFileDataSource`
/// conform, so `FileBrowsingViewModel` can be driven by either without knowing
/// the concrete type. Class-bound so the view-model can hold it in a `let` and
/// still assign `ownerDataSourceID`.
public nonisolated protocol LocalFileSource: AnyObject, FileProviding, DataSourceConnecting {
    var ownerDataSourceID: UUID { get set }
}

