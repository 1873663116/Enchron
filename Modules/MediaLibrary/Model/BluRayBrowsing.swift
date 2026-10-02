import BluRayDisc
import CryptoKit
import Foundation
import MediaSource

enum BluRayDiscBrowsingError: LocalizedError {
    case remoteDirectoryCatalogUnavailable

    var errorDescription: String? {
        switch self {
        case .remoteDirectoryCatalogUnavailable:
            "This Blu-ray folder cannot be read from the selected source."
        }
    }
}

enum BluRayDiscErrorPresentation {
    static func message(for error: any Error) -> String {
        guard let discError = error as? BluRayDiscError else {
            return error.localizedDescription
        }
        switch discError {
        case .encrypted:
            return "This encrypted Blu-ray disc is unsupported."
        case .corrupt:
            return "The Blu-ray disc is damaged or incomplete."
        case .unsupported:
            return "This item is not a supported Blu-ray disc."
        case .io(let message):
            return message
        }
    }
}

nonisolated enum BluRayCatalogProjectionLoader {
    nonisolated static func load(
        from source: BluRayDiscSource
    ) async throws -> [BluRayTitleItem] {
        let catalog = try await BluRayDisc.catalog(source: source)
        let manifest = await canonicalManifest(for: catalog.titles, source: source)
        return catalog.titles.map { title in
            BluRayTitleItem(
                playlistID: title.playlistID,
                ordinal: title.ordinal,
                optionalName: title.optionalName,
                durationSeconds: title.durationSeconds,
                isMain: title.isMain,
                catalogManifest: manifest
            )
        }
    }

    nonisolated static func canonicalManifest(
        for titles: [BluRayDiscTitle],
        source: BluRayDiscSource
    ) async -> Data {
        var lines: [String] = []
        for title in titles.sorted(by: { $0.playlistID.rawValue < $1.playlistID.rawValue }) {
            lines.append("p|\(title.playlistID.rawValue)|\(title.durationSeconds.bitPattern)|\(title.isMain)")
            for clip in title.clips {
                lines.append([
                    "c", clip.clipID,
                    String(clip.startTimeSeconds.bitPattern),
                    String(clip.inTimeSeconds.bitPattern),
                    String(clip.outTimeSeconds.bitPattern),
                    String(clip.byteStart), String(clip.byteEnd), String(clip.packetCount)
                ].joined(separator: "|"))
                for stream in clip.streams {
                    let kind = switch stream.kind {
                    case .video: "v"
                    case .audio: "a"
                    case .subtitle: "s"
                    }
                    lines.append([
                        "s", String(stream.pid), String(stream.codingType), kind,
                        stream.language ?? ""
                    ].joined(separator: "|"))
                }
            }
        }
        lines.append(contentsOf: await referencedMediaManifestLines(for: titles, source: source))
        lines.append(contentsOf: await controlFileManifestLines(for: titles, source: source))
        return Data(lines.joined(separator: "\n").utf8)
    }

    private nonisolated static func referencedMediaManifestLines(
        for titles: [BluRayDiscTitle],
        source: BluRayDiscSource
    ) async -> [String] {
        let paths = Set(titles.flatMap(\.clips).map {
            "BDMV/STREAM/\($0.clipID).m2ts"
        }).sorted()
        switch source {
        case .url(let url):
            guard url.isFileURL,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return [] }
            let root = url.lastPathComponent.caseInsensitiveCompare("BDMV") == .orderedSame
                ? url.deletingLastPathComponent()
                : url
            return paths.compactMap { path in
                let fileURL = root.appending(path: path, directoryHint: .notDirectory)
                guard let values = try? fileURL.resourceValues(forKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey
                ]), let size = values.fileSize else { return nil }
                let modified = values.contentModificationDate?.timeIntervalSince1970.bitPattern
                return [
                    "m", path, String(size), modified.map { String($0) } ?? ""
                ].joined(separator: "|")
            }
        case .fileSystem(_, let files):
            var lines: [String] = []
            for path in paths {
                guard let file = try? await files.openFile(at: path),
                      let size = try? await file.size,
                      size >= 0 else { continue }
                lines.append(["m", path, String(size), ""].joined(separator: "|"))
            }
            return lines
        }
    }

    private nonisolated static func controlFileManifestLines(
        for titles: [BluRayDiscTitle],
        source: BluRayDiscSource
    ) async -> [String] {
        let paths = Set(titles.map {
            String(format: "BDMV/PLAYLIST/%05u.mpls", $0.playlistID.rawValue)
        } + titles.flatMap(\.clips).map {
            "BDMV/CLIPINF/\($0.clipID).clpi"
        }).sorted()

        switch source {
        case .url(let url):
            guard url.isFileURL,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return [] }
            let root = url.lastPathComponent.caseInsensitiveCompare("BDMV") == .orderedSame
                ? url.deletingLastPathComponent()
                : url
            return paths.compactMap { path in
                let fileURL = root.appending(path: path, directoryHint: .notDirectory)
                guard let values = try? fileURL.resourceValues(forKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey
                ]), let size = values.fileSize else { return nil }
                let modified = values.contentModificationDate?.timeIntervalSince1970.bitPattern ?? 0
                guard size <= maximumControlFileBytes,
                      let data = try? Data(contentsOf: fileURL) else {
                    return ["f", path, String(size), String(modified), ""]
                        .joined(separator: "|")
                }
                return controlFileLine(
                    path: path,
                    size: Int64(size),
                    modifiedBitPattern: modified,
                    data: data
                )
            }
        case .fileSystem(_, let files):
            var lines: [String] = []
            for path in paths {
                guard let file = try? await files.openFile(at: path),
                      let size = try? await file.size,
                      size >= 0 else { continue }
                guard size <= Int64(maximumControlFileBytes),
                      size <= Int64(Int.max),
                      let data = try? await file.read(at: 0, count: Int(size)) else {
                    lines.append(["f", path, String(size), "", ""].joined(separator: "|"))
                    continue
                }
                lines.append(controlFileLine(
                    path: path,
                    size: size,
                    modifiedBitPattern: nil,
                    data: data
                ))
            }
            return lines
        }
    }

    private nonisolated static func controlFileLine(
        path: String,
        size: Int64,
        modifiedBitPattern: UInt64?,
        data: Data
    ) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return [
            "f", path, String(size), modifiedBitPattern.map(String.init) ?? "", digest
        ].joined(separator: "|")
    }

    private nonisolated static let maximumControlFileBytes = 16 * 1_024 * 1_024

    nonisolated static func fallbackManifest(
        for titles: [BluRayTitleItem]
    ) -> Data {
        let lines = titles
            .sorted { $0.playlistID.rawValue < $1.playlistID.rawValue }
            .map {
                "p|\($0.playlistID.rawValue)|\($0.durationSeconds.bitPattern)|\($0.isMain)"
            }
        return Data(lines.joined(separator: "\n").utf8)
    }
}

nonisolated enum BluRayDiscIdentityBasis: Sendable {
    case versioned(VersionedMediaIdentity?)
    case directory(MediaIdentity)
}

public nonisolated struct BluRayTitleItem: Identifiable, Sendable, Equatable {
    public let playlistID: BluRayPlaylistID
    public let ordinal: Int
    public let optionalName: String?
    public let durationSeconds: Double
    public let isMain: Bool
    public let versionedIdentity: VersionedMediaIdentity?
    let mediaItemID: UUID
    let catalogManifest: Data?

    public var id: BluRayPlaylistID { playlistID }

    public var displayName: String {
        if let optionalName = optionalName?.trimmingCharacters(in: .whitespacesAndNewlines),
           optionalName.isEmpty == false {
            return optionalName
        }
        return String(format: "Playlist %05u", playlistID.rawValue)
    }

    public init(
        playlistID: BluRayPlaylistID,
        ordinal: Int,
        optionalName: String?,
        durationSeconds: Double,
        isMain: Bool,
        versionedIdentity: VersionedMediaIdentity? = nil,
        mediaItemID: UUID = UUID(),
        catalogManifest: Data? = nil
    ) {
        self.playlistID = playlistID
        self.ordinal = ordinal
        self.optionalName = optionalName
        self.durationSeconds = durationSeconds
        self.isMain = isMain
        self.versionedIdentity = versionedIdentity
        self.mediaItemID = mediaItemID
        self.catalogManifest = catalogManifest
    }
}

nonisolated struct BluRayBrowseLevel: @unchecked Sendable {
    nonisolated enum Source: @unchecked Sendable {
        case image(
            file: FileBrowsingDomain.MediaFile,
            resolved: ResolvedMediaSource
        )
        case localFolder(
            folder: FileBrowsingDomain.MediaFolder,
            rootURL: URL,
            accessLease: MediaAccessLease?
        )
        case remoteFolder(
            folder: FileBrowsingDomain.MediaFolder,
            source: BluRayDiscSource
        )

        var url: URL {
            switch self {
            case .image(_, let resolved): return resolved.url
            case .localFolder(_, let rootURL, _): return rootURL
            case .remoteFolder(_, let source): return source.rootURL
            }
        }

        var displayName: String {
            switch self {
            case .image(let file, _):
                return (file.name as NSString).deletingPathExtension
            case .localFolder(let folder, _, _), .remoteFolder(let folder, _):
                return folder.name.caseInsensitiveCompare("BDMV") == .orderedSame
                    ? folder.url.deletingLastPathComponent().lastPathComponent
                    : folder.name
            }
        }

        var accessLease: MediaAccessLease? {
            switch self {
            case .image(_, let resolved): return resolved.accessLease
            case .localFolder(_, _, let accessLease): return accessLease
            case .remoteFolder: return nil
            }
        }

        var byteStreamHandle: MediaByteStreamHandle? {
            if case .image(_, let resolved) = self {
                return resolved.byteStreamHandle
            }
            return nil
        }

        var discSource: BluRayDiscSource {
            switch self {
            case .image(_, let resolved): return .url(resolved.url)
            case .localFolder(_, let rootURL, _): return .url(rootURL)
            case .remoteFolder(_, let source): return source
            }
        }

        var sizeInBytes: Int64? {
            if case .image(let file, _) = self { return file.sizeInBytes }
            return nil
        }
    }

    let source: Source
    let titles: [BluRayTitleItem]
    let parentFiles: [FileBrowsingDomain.MediaFile]
    let parentFolders: [FileBrowsingDomain.MediaFolder]
    let parentCanNavigateUp: Bool
    let parentRootDisplayName: String

    var identityComponent: String {
        "bluray:\(source.url.absoluteString)"
    }
}

nonisolated struct LibraryBluRayBrowseLevel: @unchecked Sendable {
    let reference: FileBrowsingDomain.MediaReference
    let resolved: ResolvedMediaSource
    let source: BluRayDiscSource
    let titles: [BluRayTitleItem]
}
