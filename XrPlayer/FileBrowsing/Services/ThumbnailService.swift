import CoreGraphics
import Foundation

/// Thumbnail loading and caching service for the FileBrowsing context.
///
/// Owned by the app layer and injected via the SwiftUI environment.
/// Manages two-level cache (NSCache hot + disk JPEG cold) and concurrent
/// extraction via dedicated `ThumbnailMPVAdapter` instances.
///
/// Lookup order: NSCache → disk JPEG → generate (Phase B cover art, then Phase A frame).
///
/// Concurrency limits:
///   - Local files: up to 3 concurrent extractions
///   - Remote files (smb:// / http:// / https://): up to 2 concurrent extractions
@Observable
public final class ThumbnailService {

    // MARK: - Singleton (used as SwiftUI environment object)

    /// Shared instance. Can be replaced in tests via environment injection.
    public static let shared = ThumbnailService()

    // MARK: - Private

    private let cache = ThumbnailCache.shared

    // Throttle parallel extractions: use separate semaphores for local vs remote
    private let localSemaphore = AsyncSemaphore(limit: 3)
    private let remoteSemaphore = AsyncSemaphore(limit: 2)

    /// In-flight tasks keyed by cache key (deduplicate concurrent requests for the same file).
    private var inFlightTasks: [String: Task<CGImage?, Never>] = [:]

    public init() {}

    // MARK: - Public API

    /// Returns a thumbnail for `file`, loading from cache or generating if needed.
    /// Returns `nil` if extraction fails or times out — never throws.
    public func thumbnail(for file: FileBrowsingDomain.MediaFile) async -> CGImage? {
        let key = ThumbnailCache.cacheKey(for: file)

        // 1. Hot path: NSCache
        if let cached = cache.memoryImage(forKey: key) {
            return cached
        }

        // 2. Warm path: disk
        if let diskImage = await Task.detached(priority: .utility) { [cache] in
            cache.diskImage(forKey: key)
        }.value {
            cache.storeInMemory(diskImage, forKey: key)
            return diskImage
        }

        // 3. Cold path: extract (deduplicate concurrent calls for the same key)
        return await deduplicatedExtraction(for: file, key: key)
    }

    // MARK: - Private: Deduplication

    private func deduplicatedExtraction(
        for file: FileBrowsingDomain.MediaFile,
        key: String
    ) async -> CGImage? {
        // If an extraction is already in flight for this key, await it
        if let existing = inFlightTasks[key] {
            return await existing.value
        }

        let task = Task<CGImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.generateThumbnail(for: file, key: key)
        }
        inFlightTasks[key] = task

        let result = await task.value

        // Remove the in-flight record (task is done)
        inFlightTasks.removeValue(forKey: key)

        return result
    }

    // MARK: - Private: Generation

    private func generateThumbnail(
        for file: FileBrowsingDomain.MediaFile,
        key: String
    ) async -> CGImage? {
        let semaphore = isRemote(file) ? remoteSemaphore : localSemaphore
        await semaphore.wait()
        defer { semaphore.signal() }

        let adapter = ThumbnailMPVAdapter()
        defer { adapter.cleanup() }

        guard let image = await adapter.extract(from: file) else { return nil }

        // Write to disk and warm the memory cache
        cache.storeInMemory(image, forKey: key)
        cache.storeToDisk(image, forKey: key)

        return image
    }

    // MARK: - Helpers

    private func isRemote(_ file: FileBrowsingDomain.MediaFile) -> Bool {
        guard let scheme = file.url.scheme?.lowercased() else { return false }
        return scheme == "smb" || scheme == "http" || scheme == "https"
    }
}

// MARK: - AsyncSemaphore

/// A simple async-compatible counting semaphore for Swift concurrency.
final class AsyncSemaphore: @unchecked Sendable {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    init(limit: Int) {
        self.count = limit
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if count > 0 {
                count -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if waiters.isEmpty {
            count += 1
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}
