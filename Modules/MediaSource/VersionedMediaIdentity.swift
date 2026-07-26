import CryptoKit
import Foundation

public struct MediaIdentity: Codable, Hashable, Sendable {
    public let storageKey: String

    private init(storageKey: String) {
        self.storageKey = storageKey
    }

    public static func local(resourceIdentifier: Data) -> Self {
        make(scope: "local-resource", components: [resourceIdentifier.base64EncodedString()])
    }

    public static func localPathFallback(canonicalPath: String) -> Self {
        make(scope: "local-path-fallback", components: [canonicalPath])
    }

    public static func photo(localIdentifier: String) -> Self {
        make(scope: "photo", components: [localIdentifier])
    }

    public static func remote(sourceKey: String, canonicalPath: String) -> Self {
        make(scope: "remote", components: [sourceKey, canonicalPath])
    }

    public static func remote(sourceID: UUID, canonicalPath: String) -> Self {
        remote(sourceKey: "legacy:\(sourceID.uuidString.lowercased())", canonicalPath: canonicalPath)
    }

    static func make(scope: String, components: [String]) -> Self {
        let canonicalValue = ([scope] + components).joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(canonicalValue.utf8))
        return Self(storageKey: digest.map { String(format: "%02x", $0) }.joined())
    }
}

public struct ContentRevision: Codable, Equatable, Hashable, Sendable {
    public let storageKey: String

    private init(storageKey: String) {
        self.storageKey = storageKey
    }

    public static func file(
        resourceIdentifier: Data,
        sizeInBytes: Int64,
        modifiedAt: Date
    ) -> Self {
        make(components: [
            "file",
            resourceIdentifier.base64EncodedString(),
            String(sizeInBytes),
            String(modifiedAt.timeIntervalSince1970.bitPattern),
        ])
    }

    public static func photo(localIdentifier: String, versionToken: String) -> Self {
        make(components: ["photo", localIdentifier, versionToken])
    }

    public static func remote(entityTag: String, sizeInBytes: Int64) -> Self {
        make(components: ["remote", entityTag, String(sizeInBytes)])
    }

    public static func remote(modifiedAt: Date, sizeInBytes: Int64) -> Self {
        make(components: [
            "remote-metadata",
            String(modifiedAt.timeIntervalSince1970.bitPattern),
            String(sizeInBytes),
        ])
    }

    private static func make(components: [String]) -> Self {
        let canonicalValue = components.joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(canonicalValue.utf8))
        return Self(storageKey: digest.map { String(format: "%02x", $0) }.joined())
    }
}

enum RemoteMediaVersionResolver {
    static func resolve(
        sourceKey: String,
        canonicalPath: String,
        entityTag: String?,
        sizeInBytes: Int64,
        modifiedAt: Date
    ) -> VersionedMediaIdentity? {
        let revision: ContentRevision
        if let entityTag = entityTag?.trimmingCharacters(in: .whitespacesAndNewlines),
           entityTag.isEmpty == false {
            revision = .remote(entityTag: entityTag, sizeInBytes: sizeInBytes)
        } else {
            guard modifiedAt != .distantPast,
                  modifiedAt.timeIntervalSince1970.isFinite else { return nil }
            revision = .remote(modifiedAt: modifiedAt, sizeInBytes: sizeInBytes)
        }
        return VersionedMediaIdentity(
            mediaIdentity: .remote(sourceKey: sourceKey, canonicalPath: canonicalPath),
            contentRevision: revision
        )
    }

    static func resolve(
        sourceID: UUID,
        canonicalPath: String,
        entityTag: String?,
        sizeInBytes: Int64,
        modifiedAt: Date
    ) -> VersionedMediaIdentity? {
        resolve(
            sourceKey: "legacy:\(sourceID.uuidString.lowercased())",
            canonicalPath: canonicalPath,
            entityTag: entityTag,
            sizeInBytes: sizeInBytes,
            modifiedAt: modifiedAt
        )
    }
}

public struct VersionedMediaIdentity: Codable, Equatable, Hashable, Sendable {
    public let mediaIdentity: MediaIdentity
    public let contentRevision: ContentRevision

    public init(mediaIdentity: MediaIdentity, contentRevision: ContentRevision) {
        self.mediaIdentity = mediaIdentity
        self.contentRevision = contentRevision
    }

    package static func remote(
        sourceKey: String,
        canonicalPath: String,
        entityTag: String?,
        sizeInBytes: Int64,
        modifiedAt: Date
    ) -> Self? {
        RemoteMediaVersionResolver.resolve(
            sourceKey: sourceKey,
            canonicalPath: canonicalPath,
            entityTag: entityTag,
            sizeInBytes: sizeInBytes,
            modifiedAt: modifiedAt
        )
    }

    package static func local(_ url: URL) -> Self? {
        LocalMediaVersionResolver.resolve(url)
    }

    package static func localIdentity(_ url: URL) -> MediaIdentity? {
        LocalMediaVersionResolver.resolveIdentity(url)
    }
}

enum LocalMediaVersionResolver {
    static func resolveIdentity(_ url: URL) -> MediaIdentity? {
        guard url.isFileURL else { return nil }
        if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
           let resourceIdentifier = values.fileResourceIdentifier {
            let identifierData = (resourceIdentifier as? Data)
                ?? Data(String(reflecting: resourceIdentifier).utf8)
            return .local(resourceIdentifier: identifierData)
        }
        return .localPathFallback(canonicalPath: url.standardizedFileURL.path)
    }

    static func resolve(_ url: URL) -> VersionedMediaIdentity? {
        guard url.isFileURL,
              let values = try? url.resourceValues(forKeys: [
                .fileResourceIdentifierKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ]),
              let resourceIdentifier = values.fileResourceIdentifier,
              let size = values.fileSize,
              let modifiedAt = values.contentModificationDate else {
            return nil
        }

        let identifierData = (resourceIdentifier as? Data)
            ?? Data(String(reflecting: resourceIdentifier).utf8)

        return VersionedMediaIdentity(
            mediaIdentity: .local(resourceIdentifier: identifierData),
            contentRevision: .file(
                resourceIdentifier: identifierData,
                sizeInBytes: Int64(size),
                modifiedAt: modifiedAt
            )
        )
    }
}
