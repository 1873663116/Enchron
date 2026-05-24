import CoreGraphics
import Foundation
import ImageIO

/// Two-level thumbnail cache: NSCache (hot) + disk JPEG (cold).
///
/// Cache key: SHA256(standardizedPath + modifiedAt.timeIntervalSince1970) → first 16 bytes hex.
/// Disk location: Library/Caches/thumbnails/<key>.jpg
/// System may evict disk cache on low storage (Library/Caches is non-persistent).
nonisolated final class ThumbnailCache: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = ThumbnailCache()

    // MARK: - Private

    private let memoryCache = NSCache<NSString, CGImageWrapper>()
    private let diskCacheURL: URL
    private let ioQueue = DispatchQueue(label: "xrplayer.thumbnailcache.io", qos: .utility)

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        diskCacheURL = cachesDir.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: diskCacheURL, withIntermediateDirectories: true)

        // Limit memory cache to ~60 thumbnails (typical 320×180 JPEG ~50KB each = ~3MB)
        memoryCache.countLimit = 60
    }

    // MARK: - Cache Key

    /// Derive a stable cache key from path + modifiedAt.
    static func cacheKey(for file: FileBrowsingDomain.MediaFile) -> String {
        let normalized: String
        if file.url.isFileURL {
            normalized = file.url.standardizedFileURL.path
        } else {
            normalized = file.url.absoluteString
        }
        let input = normalized + String(file.modifiedAt.timeIntervalSince1970)
        return sha256Hex(input)
    }

    // MARK: - Memory Cache

    func memoryImage(forKey key: String) -> CGImage? {
        memoryCache.object(forKey: key as NSString)?.image
    }

    func storeInMemory(_ image: CGImage, forKey key: String) {
        memoryCache.setObject(CGImageWrapper(image), forKey: key as NSString)
    }

    // MARK: - Disk Cache

    /// Synchronously checks disk. Call from a background context.
    func diskImage(forKey key: String) -> CGImage? {
        let url = diskURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return cgImage(from: data)
    }

    /// Asynchronously writes JPEG to disk.
    func storeToDisk(_ image: CGImage, forKey key: String) {
        ioQueue.async { [diskCacheURL] in
            let url = diskCacheURL.appendingPathComponent(key + ".jpg")
            guard let data = jpegData(from: image, quality: 0.72) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Convenience

    func diskURL(for key: String) -> URL {
        diskCacheURL.appendingPathComponent(key + ".jpg")
    }

    // MARK: - Private Helpers

    private static func sha256Hex(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return UUID().uuidString }
        var digest = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            CC_SHA256(base, CC_LONG(data.count), &digest)
        }
        // Take first 16 bytes (128 bits) — sufficient for collision-free key space
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - CGImageWrapper (NSCache value must be class)

private nonisolated final class CGImageWrapper: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

// MARK: - JPEG Encoding / Decoding

private nonisolated func jpegData(from image: CGImage, quality: Double) -> Data? {
    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        mutableData, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutableData as Data
}

private nonisolated func cgImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// MARK: - CommonCrypto import shim

import CommonCrypto
