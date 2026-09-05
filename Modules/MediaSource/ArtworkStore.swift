import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public struct ArtworkKey: Sendable, Equatable, Hashable {
    fileprivate let storageKey: String

    public init(mediaIdentity: MediaIdentity) {
        storageKey = "media-\(mediaIdentity.storageKey)"
    }

    public init(serverID: String, itemID: String, imageTag: String) {
        let input = "emby|\(serverID)|\(itemID)|\(imageTag)"
        storageKey = SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public init(remoteImageURL: URL) {
        storageKey = SHA256.hash(data: Data("alpha-aware|\(remoteImageURL.absoluteString)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    #if DEBUG
    public init?(debugStorageKey: String) {
        guard debugStorageKey.hasPrefix("media-"),
              debugStorageKey.count == 70,
              debugStorageKey.dropFirst(6).allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        storageKey = debugStorageKey
    }

    public var debugStorageKey: String { storageKey }
    #endif
}

#if DEBUG
public struct ArtworkDebugIdentity: Sendable, Equatable {
    public let artworkKey: String
    public let digest: String
    public let bytes: Int
    public let width: Int
    public let height: Int

    public init(
        artworkKey: String,
        digest: String,
        bytes: Int,
        width: Int,
        height: Int
    ) {
        self.artworkKey = artworkKey
        self.digest = digest
        self.bytes = bytes
        self.width = width
        self.height = height
    }
}

public struct ArtworkStoreDebugEntry: Codable, Sendable, Equatable {
    public let artworkKey: String
    public let digest: String
    public let bytes: Int64
    public let hasValidStorageName: Bool

    public init(
        artworkKey: String,
        digest: String,
        bytes: Int64,
        hasValidStorageName: Bool
    ) {
        self.artworkKey = artworkKey
        self.digest = digest
        self.bytes = bytes
        self.hasValidStorageName = hasValidStorageName
    }
}

public struct ArtworkStoreDebugSnapshot: Codable, Sendable, Equatable {
    public static let schemaValue = "enchron.regression.artwork-store-state@1"

    public let schema: String
    public let storeIdentity: String
    public let digest: String
    public let entryCount: Int
    public let entries: [ArtworkStoreDebugEntry]
    public let totalBytes: Int64
    public let invalidFileCount: Int

    public init(
        storeIdentity: String,
        digest: String,
        entries: [ArtworkStoreDebugEntry],
        invalidFileCount: Int
    ) {
        self.schema = Self.schemaValue
        self.storeIdentity = storeIdentity
        self.digest = digest
        self.entryCount = entries.count
        self.entries = entries
        self.totalBytes = entries.reduce(0) { $0 + $1.bytes }
        self.invalidFileCount = invalidFileCount
    }
}
#endif

public final class ArtworkStore: @unchecked Sendable {
    public enum StoreError: Error {
        case encodingFailed
    }

    public static let shared = ArtworkStore()

    private final class ImageBox: NSObject {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let memory = NSCache<NSString, ImageBox>()
    private let rootURL: URL
    private let queue = DispatchQueue(label: "app.enchron.artwork-store", qos: .utility)

    public init(fileManager: FileManager = .default) {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = caches.appending(path: "artwork", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    #if DEBUG
    public init(debugRootURL: URL) {
        rootURL = debugRootURL.standardizedFileURL
        try? FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }
    #endif

    public func image(for key: ArtworkKey) -> CGImage? {
        if let image = memory.object(forKey: key.storageKey as NSString)?.image { return image }
        let image = queue.sync { () -> CGImage? in
            guard let data = try? Data(contentsOf: diskURL(for: key)),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let image { memory.setObject(ImageBox(image), forKey: key.storageKey as NSString) }
        return image
    }

    public func fileURL(for key: ArtworkKey) -> URL? {
        let url = diskURL(for: key)
        return queue.sync {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date else { return nil }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = String(Int(modified.timeIntervalSince1970 * 1000))
            return components?.url ?? url
        }
    }

    public func store(_ image: CGImage, for key: ArtworkKey) throws {
        let data = try Self.encodedData(image)
        try queue.sync {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try data.write(to: diskURL(for: key), options: .atomic)
        }
        memory.setObject(ImageBox(image), forKey: key.storageKey as NSString)
    }

    public static func carriesAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        @unknown default:
            true
        }
    }

    private static func encodedData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let alpha = carriesAlpha(image)
        guard let destination = CGImageDestinationCreateWithData(
            data,
            (alpha ? "public.png" : "public.jpeg") as CFString,
            1,
            nil
        ) else { throw StoreError.encodingFailed }
        let options: [CFString: Any] = alpha
            ? [:]
            : [kCGImageDestinationLossyCompressionQuality: 0.72]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw StoreError.encodingFailed }
        return data as Data
    }

    #if DEBUG
    public func debugEncodedIdentity(
        _ image: CGImage,
        for key: ArtworkKey
    ) throws -> ArtworkDebugIdentity {
        let data = try Self.encodedData(image)
        return ArtworkDebugIdentity(
            artworkKey: key.storageKey,
            digest: Self.digest(data),
            bytes: data.count,
            width: image.width,
            height: image.height
        )
    }

    public func debugStoredIdentity(for key: ArtworkKey) -> ArtworkDebugIdentity? {
        queue.sync {
            let url = diskURL(for: key)
            guard let data = try? Data(contentsOf: url),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return ArtworkDebugIdentity(
                artworkKey: key.storageKey,
                digest: Self.digest(data),
                bytes: data.count,
                width: image.width,
                height: image.height
            )
        }
    }

    public func debugSnapshot(
        fileManager: FileManager = .default
    ) -> ArtworkStoreDebugSnapshot {
        queue.sync { [rootURL] in
            let resourceKeys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .fileSizeKey
            ]
            let files = (try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )) ?? []
            let entries = files.compactMap { fileURL -> ArtworkStoreDebugEntry? in
                guard (try? fileURL.resourceValues(forKeys: resourceKeys).isRegularFile)
                    == true,
                      let data = try? Data(contentsOf: fileURL) else { return nil }
                let isJPEG = fileURL.pathExtension == "jpg"
                let key = isJPEG
                    ? fileURL.deletingPathExtension().lastPathComponent
                    : fileURL.lastPathComponent
                return ArtworkStoreDebugEntry(
                    artworkKey: key,
                    digest: Self.digest(data),
                    bytes: Int64(data.count),
                    hasValidStorageName: isJPEG && Self.isArtworkStorageKey(key)
                )
            }
            .sorted { $0.artworkKey < $1.artworkKey }
            var hasher = SHA256()
            for entry in entries {
                hasher.update(data: Data(entry.artworkKey.utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: Data(entry.digest.utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: Data(String(entry.bytes).utf8))
                hasher.update(data: Data([0]))
                hasher.update(data: Data(String(entry.hasValidStorageName).utf8))
                hasher.update(data: Data([10]))
            }
            return ArtworkStoreDebugSnapshot(
                storeIdentity: Self.digest(
                    SHA256.hash(data: Data(rootURL.standardizedFileURL.path.utf8))
                ),
                digest: Self.digest(hasher.finalize()),
                entries: entries,
                invalidFileCount: entries.filter { $0.hasValidStorageName == false }.count
            )
        }
    }

    private static func digest(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func digest(_ digest: SHA256.Digest) -> String {
        "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func isArtworkStorageKey(_ value: String) -> Bool {
        let digest = value.hasPrefix("media-") ? value.dropFirst("media-".count) : value[...]
        return digest.utf8.count == 64 && digest.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }
    #endif

    public func diskUsageInBytes() async -> Int64 {
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: rootURL,
                    includingPropertiesForKeys: Array(keys)
                )) ?? []
                let total = urls.reduce(into: Int64(0)) { result, url in
                    let values = try? url.resourceValues(forKeys: keys)
                    if values?.isRegularFile == true { result += Int64(values?.fileSize ?? 0) }
                }
                continuation.resume(returning: total)
            }
        }
    }

    public func clear() async {
        memory.removeAllObjects()
        await withCheckedContinuation { continuation in
            queue.async { [rootURL] in
                try? FileManager.default.removeItem(at: rootURL)
                try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
                continuation.resume()
            }
        }
    }

    private func diskURL(for key: ArtworkKey) -> URL {
        rootURL.appending(path: "\(key.storageKey).jpg")
    }
}
