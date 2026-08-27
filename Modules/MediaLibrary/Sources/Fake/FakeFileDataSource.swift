import Foundation
import MediaSource

nonisolated final class FakeFileDataSource: LocalFileSource, @unchecked Sendable {

    public enum FailureMode: Sendable {
        case none
        case listingFails(message: String)
    }

    public var ownerDataSourceID: UUID
    public private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected

    private let latency: Duration?
    private let failureMode: FailureMode
    private let catalog: Catalog

    init(
        ownerDataSourceID: UUID = UUID(),
        latency: Duration? = nil,
        failureMode: FailureMode = .none,
        catalog: Catalog = .demo
    ) {
        self.ownerDataSourceID = ownerDataSourceID
        self.latency = latency
        self.failureMode = failureMode
        self.catalog = catalog
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connecting
        try await applyLatency()
        connectionStatus = .connected
    }

    public func disconnect() {
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        try await applyLatency()
        try throwIfFailing()
        return catalog.files(at: Self.normalize(path), ownerDataSourceID: ownerDataSourceID).filter {
            FileBrowsingDomain.FileFilter.playable.matches(fileURL: $0.url)
        }
    }

    public func listSubtitleFiles(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        try await applyLatency()
        try throwIfFailing()
        return catalog.files(at: Self.normalize(path), ownerDataSourceID: ownerDataSourceID).filter {
            FileBrowsingDomain.FileFilter.externalSubtitles.matches(fileURL: $0.url)
        }
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        try await applyLatency()
        try throwIfFailing()
        return catalog.folders(at: Self.normalize(path), ownerDataSourceID: ownerDataSourceID)
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        item.url
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        try await applyLatency()
        try throwIfFailing()
        let files = catalog.files(at: Self.normalize(folder.path), ownerDataSourceID: ownerDataSourceID)
        return sortBy.sorted(files)
    }

    public func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> ResolvedMediaSource {
        ResolvedMediaSource(url: file.url)
    }

    private static func normalize(_ path: String) -> String {
        (path.isEmpty || path == ".") ? "/" : path
    }

    private func applyLatency() async throws {
        if let latency {
            try await Task.sleep(for: latency)
        }
    }

    private func throwIfFailing() throws {
        if case let .listingFails(message) = failureMode {
            connectionStatus = .failed(message)
            throw FakeFileDataSourceError.listingFailed(message)
        }
    }
}

public nonisolated enum FakeFileDataSourceError: LocalizedError {
    case listingFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .listingFailed(message):
            return message
        }
    }
}

nonisolated extension FakeFileDataSource {

    public struct Catalog: Sendable {
        let filesByPath: [String: [FileSeed]]
        let folderNamesByPath: [String: [String]]

        public init(filesByPath: [String: [FileSeed]], folderNamesByPath: [String: [String]]) {
            self.filesByPath = filesByPath
            self.folderNamesByPath = folderNamesByPath
        }

        func files(at path: String, ownerDataSourceID: UUID) -> [FileBrowsingDomain.MediaFile] {
            (filesByPath[path] ?? []).map { $0.makeMediaFile(parentPath: path) }
        }

        func folders(at path: String, ownerDataSourceID: UUID) -> [FileBrowsingDomain.MediaFolder] {
            (folderNamesByPath[path] ?? []).map { name in
                let childPath = path == "/" ? "/\(name)" : "\(path)/\(name)"
                return FileBrowsingDomain.MediaFolder(
                    name: name,
                    dataSourceID: ownerDataSourceID,
                    path: childPath,
                    url: FileSeed.fakeURL(forPath: childPath)
                )
            }
        }

        public static let demo = Catalog(
            filesByPath: [
                "/": [
                    FileSeed("Interstellar.mkv", gigabytes: 42.8, daysAgo: 3),
                    FileSeed("The Matrix.mkv", gigabytes: 38.2, daysAgo: 12),
                    FileSeed("Dune Part Two.mkv", gigabytes: 56.1, daysAgo: 1),
                    FileSeed("Arrival.mkv", gigabytes: 28.4, daysAgo: 30),
                    FileSeed("Blade Runner 2049.mkv", gigabytes: 45.6, daysAgo: 7),
                    FileSeed("Ex Machina.mov", gigabytes: 22.7, daysAgo: 21),
                    FileSeed("Gravity.mkv", gigabytes: 18.9, daysAgo: 45),
                    FileSeed("2001 A Space Odyssey.mkv", gigabytes: 35.1, daysAgo: 60),
                    FileSeed("The Martian.mkv", gigabytes: 31.5, daysAgo: 5)
                ],
                "/Documentaries": [
                    FileSeed("Cosmos.mkv", gigabytes: 12.4, daysAgo: 9),
                    FileSeed("Planet Earth.mkv", gigabytes: 64.2, daysAgo: 15)
                ]
            ],
            folderNamesByPath: [
                "/": ["Documentaries", "Empty"]
            ]
        )

        public static let demoDeep = Catalog(
            filesByPath: [
                "/": [
                    FileSeed("Interstellar.mkv", gigabytes: 42.8, daysAgo: 3),
                    FileSeed("Dune Part Two.mkv", gigabytes: 56.1, daysAgo: 1),
                    FileSeed("Arrival.mkv", gigabytes: 28.4, daysAgo: 30)
                ],
                "/Movies": [
                    FileSeed("The Martian.mkv", gigabytes: 31.5, daysAgo: 5)
                ],
                "/Movies/Sci-Fi": [
                    FileSeed("Blade Runner 2049.mkv", gigabytes: 45.6, daysAgo: 7),
                    FileSeed("Ex Machina.mov", gigabytes: 22.7, daysAgo: 21),
                    FileSeed("2001 A Space Odyssey.mkv", gigabytes: 35.1, daysAgo: 60)
                ],
                "/Movies/Sci-Fi/Series": [
                    FileSeed("Foundation S01E01.mkv", gigabytes: 8.2, daysAgo: 14),
                    FileSeed("Foundation S01E02.mkv", gigabytes: 8.6, daysAgo: 13),
                    FileSeed("Foundation S01E03.mkv", gigabytes: 8.4, daysAgo: 12)
                ],
                "/Movies/Drama": [
                    FileSeed("Oppenheimer.mkv", gigabytes: 61.3, daysAgo: 8),
                    FileSeed("The Whale.mkv", gigabytes: 19.7, daysAgo: 40)
                ],
                "/Movies/Animation": [
                    FileSeed("Spirited Away.mkv", gigabytes: 24.1, daysAgo: 90),
                    FileSeed("Akira.mkv", gigabytes: 27.8, daysAgo: 120)
                ],
                "/Documentaries": [
                    FileSeed("Cosmos.mkv", gigabytes: 12.4, daysAgo: 9),
                    FileSeed("Planet Earth.mkv", gigabytes: 64.2, daysAgo: 15)
                ],
                "/Concerts": [
                    FileSeed("Live at Pompeii.mkv", gigabytes: 33.0, daysAgo: 50)
                ]
            ],
            folderNamesByPath: [
                "/": ["Movies", "Documentaries", "Concerts", "Empty"],
                "/Movies": ["Sci-Fi", "Drama", "Animation"],
                "/Movies/Sci-Fi": ["Series"],
                "/Concerts": ["Empty Nested"]
            ]
        )
    }

    public struct FileSeed: Sendable {
        let name: String
        let sizeInBytes: Int64
        let modifiedAt: Date
        let fileExtension: String

        private static let epochBase = Date(timeIntervalSince1970: 1_704_067_200)

        init(_ name: String, gigabytes: Double, daysAgo: Int) {
            self.name = name
            self.sizeInBytes = Int64(gigabytes * 1_000_000_000)
            self.modifiedAt = Self.epochBase.addingTimeInterval(TimeInterval(-daysAgo * 86_400))
            self.fileExtension = (name as NSString).pathExtension
        }

        func makeMediaFile(parentPath: String) -> FileBrowsingDomain.MediaFile {
            let childPath = parentPath == "/" ? "/\(name)" : "\(parentPath)/\(name)"
            return FileBrowsingDomain.MediaFile(
                name: name,
                sizeInBytes: sizeInBytes,
                modifiedAt: modifiedAt,
                fileExtension: fileExtension,
                url: Self.fakeURL(forPath: childPath)
            )
        }

        static func fakeURL(forPath path: String) -> URL {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            return URL(string: "fake://local\(encoded)") ?? URL(string: "fake://local")!
        }
    }
}
