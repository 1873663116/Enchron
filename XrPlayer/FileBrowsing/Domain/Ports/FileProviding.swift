import Foundation

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
