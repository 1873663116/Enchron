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
        storageKey = SHA256.hash(data: Data(remoteImageURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

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
        return queue.sync { FileManager.default.fileExists(atPath: url.path) ? url : nil }
    }

    public func store(_ image: CGImage, for key: ArtworkKey) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { throw StoreError.encodingFailed }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw StoreError.encodingFailed }
        try queue.sync {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try (data as Data).write(to: diskURL(for: key), options: .atomic)
        }
        memory.setObject(ImageBox(image), forKey: key.storageKey as NSString)
    }

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
