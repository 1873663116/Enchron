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

actor BluRayCatalogCache {
    static let shared = BluRayCatalogCache()

    private struct PersistedCatalog: Codable {
        let catalog: BluRayDiscCatalog
        let manifest: Data
    }

    private var entries: [VersionedMediaIdentity: LoadedBluRayCatalog] = [:]
    private var order: [VersionedMediaIdentity] = []
    private let limit = 8
    private let directory: URL?

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let target = base?.appendingPathComponent("BluRayCatalogs", isDirectory: true)
        if let target {
            try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }
        directory = target
    }

    func value(for identity: VersionedMediaIdentity) -> LoadedBluRayCatalog? {
        if let catalog = entries[identity] {
            touch(identity)
            return catalog
        }
        guard let catalog = loadFromDisk(identity) else { return nil }
        entries[identity] = catalog
        touch(identity)
        return catalog
    }

    func store(_ catalog: LoadedBluRayCatalog, for identity: VersionedMediaIdentity) {
        entries[identity] = catalog
        touch(identity)
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
        persist(catalog, for: identity)
    }

    private func touch(_ identity: VersionedMediaIdentity) {
        if let index = order.firstIndex(of: identity) {
            order.remove(at: index)
        }
        order.append(identity)
    }

    private func fileURL(for identity: VersionedMediaIdentity) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(String(describing: identity).utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private func persist(_ catalog: LoadedBluRayCatalog, for identity: VersionedMediaIdentity) {
        guard let url = fileURL(for: identity) else { return }
        let payload = PersistedCatalog(catalog: catalog.catalog, manifest: catalog.manifest)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
        pruneDiskCache()
    }

    private func pruneDiskCache() {
        guard let directory else { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let listing = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        ) else { return }
        let dated = listing.compactMap { file -> (URL, Date)? in
            let values = try? file.resourceValues(forKeys: Set(keys))
            guard let date = values?.contentModificationDate else { return nil }
            return (file, date)
        }
        let ordered = dated.sorted { $0.1 > $1.1 }
        for (file, _) in ordered.dropFirst(limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func loadFromDisk(_ identity: VersionedMediaIdentity) -> LoadedBluRayCatalog? {
        guard let url = fileURL(for: identity),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(PersistedCatalog.self, from: data) else {
            return nil
        }
        let now = Date()
        try? FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: url.path
        )
        return LoadedBluRayCatalog(catalog: payload.catalog, manifest: payload.manifest)
    }
}

nonisolated struct LoadedBluRayCatalog: Sendable {
    let catalog: BluRayDiscCatalog
    let manifest: Data

    func present(
        sourceName: String,
        identity: VersionedMediaIdentity?
    ) throws -> (content: BluRayDiscContent, titles: [BluRayTitleItem]) {
        let content = try BluRayDiscContent.project(catalog, sourceName: sourceName)
        let cloneIDs = BluRayDiscContent.exactDuplicateIDs(in: catalog.titles)
        let byID = Dictionary(
            catalog.titles.map { ($0.playlistID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let programs = (content.primaryTitles + content.groups.flatMap(\.titles))
            .filter { program in
                guard !cloneIDs.contains(program.playlistID),
                      let title = byID[program.playlistID] else { return false }
                return isPlayable(title, among: catalog.titles)
            }
            .sorted { lhs, rhs in
                let leftMain = byID[lhs.playlistID]?.isMain ?? lhs.isMain
                let rightMain = byID[rhs.playlistID]?.isMain ?? rhs.isMain
                if leftMain != rightMain { return leftMain }
                if lhs.durationSeconds != rhs.durationSeconds {
                    return lhs.durationSeconds > rhs.durationSeconds
                }
                return lhs.playlistID.rawValue < rhs.playlistID.rawValue
            }
        let titles = programs.enumerated().map { ordinal, program in
            BluRayTitleItem(
                playlistID: program.playlistID,
                ordinal: ordinal,
                displayName: program.displayName,
                durationSeconds: program.durationSeconds,
                isMain: byID[program.playlistID]?.isMain ?? program.isMain,
                versionedIdentity: identity.map {
                    .bluRayPlaylist(disc: $0, playlistID: program.playlistID.rawValue)
                },
                catalogManifest: manifest
            )
        }
        return (content, titles)
    }

    private func isPlayable(_ title: BluRayDiscTitle, among titles: [BluRayDiscTitle]) -> Bool {
        guard title.durationSeconds >= 20 else { return false }
        guard title.clips.contains(where: { clip in
            clip.streams.contains { $0.kind == .video }
        }) else { return false }
        guard !title.clips.allSatisfy({ $0.stillMode != 0 }) else { return false }
        let clipIDs = Set(title.clips.map(\.clipID))
        if clipIDs.count <= 4 && title.clips.count >= 8 { return false }
        guard title.clips.count > 1 else { return true }
        let contained = titles.filter { other in
            guard other.playlistID != title.playlistID, !other.clips.isEmpty else { return false }
            return Set(other.clips.map(\.clipID)).isSubset(of: clipIDs)
        }
        return contained.count < 2
    }
}

nonisolated enum BluRayCatalogProjectionLoader {
    nonisolated static func load(
        from source: BluRayDiscSource
    ) async throws -> LoadedBluRayCatalog {
        let catalog = try await BluRayDisc.catalog(source: source)
        let manifest = await canonicalManifest(for: catalog.titles, source: source)
        return LoadedBluRayCatalog(catalog: catalog, manifest: manifest)
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
        for titles: [BluRayDiscTitle]
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
    public let displayName: String
    public let durationSeconds: Double
    public let isMain: Bool
    public let versionedIdentity: VersionedMediaIdentity?
    let mediaItemID: UUID
    let catalogManifest: Data?

    public var id: BluRayPlaylistID { playlistID }

    public init(
        playlistID: BluRayPlaylistID,
        ordinal: Int,
        displayName: String,
        durationSeconds: Double,
        isMain: Bool,
        versionedIdentity: VersionedMediaIdentity? = nil,
        mediaItemID: UUID = UUID(),
        catalogManifest: Data? = nil
    ) {
        self.playlistID = playlistID
        self.ordinal = ordinal
        self.displayName = displayName
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
    let content: BluRayDiscContent
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
    let content: BluRayDiscContent
    let titles: [BluRayTitleItem]
}
