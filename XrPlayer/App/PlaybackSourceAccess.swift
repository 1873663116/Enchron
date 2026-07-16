import Foundation

private nonisolated final class RetainedPlaybackSource: @unchecked Sendable {
    let value: AnyObject

    init(_ value: AnyObject) {
        self.value = value
    }
}

nonisolated final class PlaybackSourceAccess: @unchecked Sendable {
    private let lock = NSLock()
    private let acquireAction: @Sendable () -> Bool
    private let releaseAction: @Sendable () -> Void
    private var isActive: Bool

    init(release: @escaping @Sendable () -> Void) {
        acquireAction = { false }
        releaseAction = release
        isActive = true
    }

    init?(
        acquire: @escaping @Sendable () -> Bool,
        release: @escaping @Sendable () -> Void
    ) {
        acquireAction = acquire
        releaseAction = release
        isActive = false
        guard acquire() else { return nil }
        isActive = true
    }

    static func securityScoped(_ url: URL) -> PlaybackSourceAccess? {
        PlaybackSourceAccess(
            acquire: { url.startAccessingSecurityScopedResource() },
            release: { url.stopAccessingSecurityScopedResource() }
        )
    }

    static func retaining(_ owner: AnyObject, securityScoped url: URL) -> PlaybackSourceAccess {
        let retainedOwner = RetainedPlaybackSource(owner)
        let accessStarted = url.startAccessingSecurityScopedResource()
        return PlaybackSourceAccess {
            _ = retainedOwner.value
            if accessStarted { url.stopAccessingSecurityScopedResource() }
        }
    }

    static func temporaryFile(_ url: URL) -> PlaybackSourceAccess {
        PlaybackSourceAccess {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: url)
            let directory = url.deletingLastPathComponent()
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    func ensureActive() -> Bool {
        lock.withLock {
            guard !isActive else { return true }
            guard acquireAction() else { return false }
            isActive = true
            return true
        }
    }

    func release() {
        let shouldRelease = lock.withLock {
            guard isActive else { return false }
            isActive = false
            return true
        }
        if shouldRelease { releaseAction() }
    }

    deinit {
        release()
    }
}

nonisolated struct ResolvedPlaybackSource: @unchecked Sendable {
    let url: URL
    let sourceAccess: PlaybackSourceAccess?

    init(url: URL, sourceAccess: PlaybackSourceAccess? = nil) {
        self.url = url
        self.sourceAccess = sourceAccess
    }

    init(_ source: FilePlaybackSource) {
        url = source.url
        sourceAccess = source.lease.map { lease in
            PlaybackSourceAccess { lease.release() }
        }
    }
}
