import Foundation

public final class MediaAccessLease: @unchecked Sendable {
    private final class RetainedOwner: @unchecked Sendable {
        let value: AnyObject

        init(_ value: AnyObject) {
            self.value = value
        }
    }

    private let acquireOperation: @Sendable () -> Bool
    private let releaseOperation: @Sendable () -> Void
    private let lock = NSLock()
    private var isActive: Bool

    public init(release: @escaping @Sendable () -> Void = {}) {
        acquireOperation = { false }
        releaseOperation = release
        isActive = true
    }

    public init?(
        acquire: @escaping @Sendable () -> Bool,
        release: @escaping @Sendable () -> Void
    ) {
        acquireOperation = acquire
        releaseOperation = release
        isActive = false
        guard ensureActive() else { return nil }
    }

    public static func securityScoped(_ url: URL) -> MediaAccessLease? {
        MediaAccessLease(
            acquire: { url.startAccessingSecurityScopedResource() },
            release: { url.stopAccessingSecurityScopedResource() }
        )
    }

    public static func retaining(_ owner: AnyObject, securityScoped url: URL) -> MediaAccessLease {
        let retainedOwner = RetainedOwner(owner)
        let accessStarted = url.startAccessingSecurityScopedResource()
        return MediaAccessLease {
            _ = retainedOwner.value
            if accessStarted { url.stopAccessingSecurityScopedResource() }
        }
    }

    public static func temporaryFile(_ url: URL) -> MediaAccessLease {
        MediaAccessLease {
            let fileManager = FileManager.default
            try? fileManager.removeItem(at: url)
            let directory = url.deletingLastPathComponent()
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    public func ensureActive() -> Bool {
        lock.withLock {
            guard !isActive else { return true }
            guard acquireOperation() else { return false }
            isActive = true
            return true
        }
    }

    public func release() {
        let shouldRelease = lock.withLock {
            guard isActive else { return false }
            isActive = false
            return true
        }
        if shouldRelease { releaseOperation() }
    }

    deinit {
        release()
    }
}
