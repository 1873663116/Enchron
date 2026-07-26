@preconcurrency import AVFoundation
import Foundation
import MediaSource
import Observation
import OSLog
@preconcurrency import Photos

private struct SendableAVAsset: @unchecked Sendable {
    nonisolated(unsafe) let value: AVAsset?

    nonisolated init(value: AVAsset?) {
        self.value = value
    }
}

private struct SendablePHAsset: @unchecked Sendable {
    let value: PHAsset

    nonisolated init(value: PHAsset) {
        self.value = value
    }
}

private enum PhotoMediaVersionResolver {
    @MainActor
    static func resolve(localIdentifier: String) -> VersionedMediaIdentity? {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        ).firstObject,
              let modifiedAt = asset.modificationDate else { return nil }
        let versionToken = [
            String(modifiedAt.timeIntervalSince1970.bitPattern),
            String(asset.duration.bitPattern),
            String(asset.pixelWidth),
            String(asset.pixelHeight),
        ].joined(separator: ":")
        return VersionedMediaIdentity(
            mediaIdentity: .photo(localIdentifier: localIdentifier),
            contentRevision: .photo(
                localIdentifier: localIdentifier,
                versionToken: versionToken
            )
        )
    }
}

@MainActor
final class MediaReferenceResolver {
    public enum ResolutionError: LocalizedError {
        case unavailableFile
        case unavailablePhoto
        case unavailableSource

        public var errorDescription: String? {
            switch self {
            case .unavailableFile:
                return "The original file is unavailable. Choose it again to restore access."
            case .unavailablePhoto:
                return "The original Photos video is unavailable or no longer shared with Enchron."
            case .unavailableSource:
                return "The original network source is unavailable. Reconnect it and try again."
            }
        }
    }

    public var resolveSourceItem: (@MainActor (
        UUID,
        String,
        FileBrowsingDomain.MediaReference
    ) async throws -> ResolvedMediaSource)?

    private let fileResolver = SecurityScopedFileReferenceResolver()
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "app.enchron", category: "PhotoResolver")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        try? fileManager.removeItem(at: Self.photoStagingRoot(fileManager: fileManager))
    }

    fileprivate func resolve(_ reference: FileBrowsingDomain.MediaReference) async throws -> ResolvedMediaSource {
        switch reference.locator {
        case .file(let bookmark, let relativePath):
            let resolved = try fileResolver.resolve(bookmark: bookmark, relativePath: relativePath)
            return ResolvedMediaSource(
                url: resolved.url,
                accessLease: resolved.access
            )
        case .photoAsset(let localIdentifier):
            return try await resolvePhoto(localIdentifier: localIdentifier)
        case .sourceItem(let dataSourceID, let path):
            guard let resolveSourceItem else { throw ResolutionError.unavailableSource }
            return try await resolveSourceItem(dataSourceID, path, reference)
        }
    }

    private func resolvePhoto(localIdentifier: String) async throws -> ResolvedMediaSource {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { throw ResolutionError.unavailablePhoto }
        let requestedAsset = await Self.requestOriginalAsset(SendablePHAsset(value: asset))
        guard let avAsset = requestedAsset.value else { throw ResolutionError.unavailablePhoto }
        if let urlAsset = avAsset as? AVURLAsset {
            let sourceAccess = MediaAccessLease.retaining(avAsset, securityScoped: urlAsset.url)
            if (try? urlAsset.url.checkResourceIsReachable()) == true {
                logger.info("Photos source resolved as a directly readable file URL")
                return ResolvedMediaSource(url: urlAsset.url, accessLease: sourceAccess)
            }
            sourceAccess.release()
        }
        return try await stageOriginalPhoto(asset)
    }

    private func stageOriginalPhoto(_ asset: PHAsset) async throws -> ResolvedMediaSource {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video })
            ?? resources.first(where: { $0.type == .pairedVideo }) else {
            throw ResolutionError.unavailablePhoto
        }

        let directory = Self.photoStagingRoot(fileManager: fileManager)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let destination = directory.appending(
            path: filename.isEmpty ? "PhotosVideo.mov" : filename
        )
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                PHAssetResourceManager.default().writeData(
                    for: resource,
                    toFile: destination,
                    options: options
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }

        logger.info("Photos source staged for FFmpeg playback file=\(destination.lastPathComponent, privacy: .public)")
        return ResolvedMediaSource(
            url: destination,
            accessLease: MediaAccessLease.temporaryFile(destination)
        )
    }

    private static func photoStagingRoot(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory
            .appending(path: "EnchronPhotosPlayback", directoryHint: .isDirectory)
    }

    private nonisolated static func requestOriginalAsset(
        _ asset: SendablePHAsset
    ) async -> SendableAVAsset {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .original

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestAVAsset(
                forVideo: asset.value,
                options: options
            ) { asset, _, _ in
                continuation.resume(returning: SendableAVAsset(value: asset))
            }
        }
    }
}

@MainActor
@Observable
public final class MediaLibraryViewModel {
    public private(set) var library: FileBrowsingDomain.MediaLibrary
    public private(set) var currentFolderID: UUID?
    public private(set) var folderPath: [UUID] = []
    public var lastErrorMessage: String?
    public private(set) var currentReferenceID: UUID?
    private var playbackCollection: [FileBrowsingDomain.MediaReference] = []
    public private(set) var referenceViewingStates: [UUID: VideoCardViewingState] = [:]

    private let store: MediaLibraryStoring
    private let resolver: MediaReferenceResolver
    private let fileManager: FileManager
    private let viewingStateProvider: MediaViewingStateProvider
    private let onPlay: @MainActor (MediaPlaybackItem) -> Void

    init(
        store: MediaLibraryStoring = UserDefaultsMediaLibraryStore(),
        resolver: MediaReferenceResolver,
        fileManager: FileManager = .default,
        viewingStateProvider: @escaping MediaViewingStateProvider = { _ in nil },
        initialLibrary: FileBrowsingDomain.MediaLibrary? = nil,
        onPlay: @escaping @MainActor (MediaPlaybackItem) -> Void
    ) {
        self.store = store
        self.resolver = resolver
        self.fileManager = fileManager
        self.viewingStateProvider = viewingStateProvider
        self.onPlay = onPlay
        if let initialLibrary {
            self.library = initialLibrary
        } else {
            self.library = (try? store.load()) ?? .init()
        }
        Task { [weak self] in await self?.loadViewingStatesForCurrentFolder() }
    }

    public var folders: [FileBrowsingDomain.LibraryFolder] {
        library.folders(in: currentFolderID)
    }

    public var references: [FileBrowsingDomain.MediaReference] {
        library.references(in: currentFolderID)
    }

    public var allFolders: [FileBrowsingDomain.LibraryFolder] {
        collectFolders(in: nil)
    }

    public var currentFolderName: String {
        currentFolderID.flatMap { library.folder(id: $0)?.name } ?? "Media Library"
    }

    public var canNavigateUp: Bool { !folderPath.isEmpty }

    public var breadcrumbFolders: [FileBrowsingDomain.LibraryFolder] {
        (folderPath + [currentFolderID].compactMap { $0 }).compactMap { library.folder(id: $0) }
    }

    public func createFolder(named name: String) {
        mutate {
            _ = try library.createFolder(named: name, in: currentFolderID)
        }
    }

    public func open(_ folder: FileBrowsingDomain.LibraryFolder) {
        if let currentFolderID { folderPath.append(currentFolderID) }
        currentFolderID = folder.id
        Task { [weak self] in await self?.loadViewingStatesForCurrentFolder() }
    }

    public func navigateUp() {
        currentFolderID = folderPath.popLast()
        Task { [weak self] in await self?.loadViewingStatesForCurrentFolder() }
    }

    public func navigateToRoot() {
        currentFolderID = nil
        folderPath.removeAll()
        Task { [weak self] in await self?.loadViewingStatesForCurrentFolder() }
    }

    public func navigate(to folderID: UUID) {
        guard let index = breadcrumbFolders.firstIndex(where: { $0.id == folderID }) else { return }
        let ids = breadcrumbFolders.prefix(index + 1).map(\.id)
        currentFolderID = ids.last
        folderPath = Array(ids.dropLast())
        Task { [weak self] in await self?.loadViewingStatesForCurrentFolder() }
    }

    public func remove(_ reference: FileBrowsingDomain.MediaReference) {
        mutate { library.removeReference(reference.id) }
    }

    public func rename(_ folder: FileBrowsingDomain.LibraryFolder, to name: String) {
        mutate { try library.renameFolder(folder.id, to: name) }
    }

    public func remove(_ folder: FileBrowsingDomain.LibraryFolder) {
        mutate { library.removeFolder(folder.id) }
    }

    public func move(_ reference: FileBrowsingDomain.MediaReference, to folderID: UUID?) {
        mutate { try library.moveReference(reference.id, to: folderID) }
    }

    public func addFiles(_ urls: [URL]) {
        mutate {
            for url in urls {
                try addFile(url)
            }
        }
    }

    public func addFolder(_ folderURL: URL) {
        mutate {
            let accessStarted = folderURL.startAccessingSecurityScopedResource()
            defer { if accessStarted { folderURL.stopAccessingSecurityScopedResource() } }
            let bookmark = try folderURL.bookmarkData(
                options: SecurityScopedFileReferenceResolver.bookmarkCreationOptions
            )
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw MediaReferenceResolver.ResolutionError.unavailableFile
            }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true,
                      FileBrowsingDomain.FileFilter.playable.matches(fileURL: url) else { continue }
                let relativePath = String(url.path.dropFirst(folderURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let reference = FileBrowsingDomain.MediaReference(
                    name: url.lastPathComponent,
                    locator: .file(bookmark: bookmark, relativePath: relativePath),
                    sizeInBytes: Int64(values.fileSize ?? 0),
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
                try library.add(reference, to: currentFolderID)
            }
        }
    }

    public func addPhotoItems(_ items: [(localIdentifier: String, name: String)]) {
        mutate {
            for item in items {
                try library.add(
                    .init(name: item.name, locator: .photoAsset(localIdentifier: item.localIdentifier)),
                    to: currentFolderID
                )
            }
        }
    }

    public func addSourceFile(
        _ file: FileBrowsingDomain.MediaFile,
        dataSource: FileBrowsingDomain.DataSource,
        path: String
    ) {
        mutate {
            try library.add(
                .init(
                    name: file.name,
                    locator: .sourceItem(dataSourceID: dataSource.id, path: path),
                    sizeInBytes: file.sizeInBytes,
                    modifiedAt: file.modifiedAt,
                    fileExtension: file.fileExtension,
                    remoteEntityTag: file.remoteEntityTag,
                    remoteSourceKey: dataSource.connectionInfo.mediaIdentitySourceKey
                ),
                to: currentFolderID
            )
        }
    }

    public func play(_ reference: FileBrowsingDomain.MediaReference) {
        playbackCollection = Self.naturalPlaybackCollection(from: references)
        Task {
            do {
                let request = try await playbackItem(for: reference)
                currentReferenceID = reference.id
                onPlay(request)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    public func nextPlaybackItem() async -> MediaPlaybackItem? {
        guard let currentReferenceID,
              let currentIndex = playbackCollection.firstIndex(where: { $0.id == currentReferenceID }),
              playbackCollection.indices.contains(currentIndex + 1) else { return nil }
        let next = playbackCollection[currentIndex + 1]
        do {
            let request = try await playbackItem(for: next)
            self.currentReferenceID = next.id
            return request
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    public var mediaCollectionSnapshot: MediaCollectionSnapshot {
        MediaCollectionSnapshot(entries: playbackCollection.map {
            MediaCollectionEntry(
                id: $0.id,
                displayName: $0.name,
                isCurrent: $0.id == currentReferenceID
            )
        })
    }

    public func playbackItem(forCollectionItemID id: UUID) async -> MediaPlaybackItem? {
        guard let reference = playbackCollection.first(where: { $0.id == id }) else { return nil }
        do {
            let request = try await playbackItem(for: reference)
            currentReferenceID = reference.id
            return request
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func playbackItem(for reference: FileBrowsingDomain.MediaReference) async throws -> MediaPlaybackItem {
        let source = try await resolver.resolve(reference)
        let versionedIdentity: VersionedMediaIdentity? = switch reference.locator {
        case .file:
            VersionedMediaIdentity.local(source.url)
        case .sourceItem(let dataSourceID, let path):
            VersionedMediaIdentity.remote(
                sourceKey: reference.remoteSourceKey
                    ?? "legacy:\(dataSourceID.uuidString.lowercased())",
                canonicalPath: path,
                entityTag: reference.remoteEntityTag,
                sizeInBytes: reference.sizeInBytes,
                modifiedAt: reference.modifiedAt
            )
        case .photoAsset(let localIdentifier):
            PhotoMediaVersionResolver.resolve(localIdentifier: localIdentifier)
        }
        let stableIdentifier = "media-library/\(reference.id.uuidString)|\(reference.sizeInBytes)|local"
        return MediaPlaybackItem(
            id: reference.id,
            url: source.url,
            displayName: reference.name,
            stableIdentifier: stableIdentifier,
            sizeInBytes: reference.sizeInBytes,
            collectionOrigin: .mediaLibrary,
            versionedIdentity: versionedIdentity,
            accessLease: source.accessLease
        )
    }

    private static func naturalPlaybackCollection(
        from references: [FileBrowsingDomain.MediaReference]
    ) -> [FileBrowsingDomain.MediaReference] {
        references.sorted {
            NaturalMediaNameOrder.lessThan($0.name, id: $0.id, $1.name, id: $1.id)
        }
    }

    private func loadViewingStatesForCurrentFolder() async {
        let snapshot = references
        var states: [UUID: VideoCardViewingState] = [:]
        for reference in snapshot {
            let identity: MediaIdentity?
            switch reference.locator {
            case .file:
                if let source = try? await resolver.resolve(reference) {
                    identity = VersionedMediaIdentity.localIdentity(source.url)
                    source.accessLease?.release()
                } else {
                    identity = nil
                }
            case .sourceItem(let dataSourceID, let path):
                identity = .remote(
                    sourceKey: reference.remoteSourceKey
                        ?? "legacy:\(dataSourceID.uuidString.lowercased())",
                    canonicalPath: path
                )
            case .photoAsset(let localIdentifier):
                identity = .photo(localIdentifier: localIdentifier)
            }
            guard let identity,
                  let state = await viewingStateProvider(identity) else { continue }
            states[reference.id] = state
        }
        guard snapshot.map(\.id) == references.map(\.id) else { return }
        referenceViewingStates = states
    }

    public func refreshViewingStates() {
        Task { await loadViewingStatesForCurrentFolder() }
    }

    private func addFile(_ url: URL) throws {
        guard FileBrowsingDomain.FileFilter.playable.matches(fileURL: url) else { return }
        let accessStarted = url.startAccessingSecurityScopedResource()
        defer { if accessStarted { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let reference = FileBrowsingDomain.MediaReference(
            name: url.lastPathComponent,
            locator: .file(
                bookmark: try url.bookmarkData(
                    options: SecurityScopedFileReferenceResolver.bookmarkCreationOptions
                ),
                relativePath: ""
            ),
            sizeInBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast
        )
        try library.add(reference, to: currentFolderID)
    }

    private func mutate(_ operation: () throws -> Void) {
        do {
            try operation()
            try store.save(library)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func collectFolders(in parentID: UUID?) -> [FileBrowsingDomain.LibraryFolder] {
        library.folders(in: parentID).flatMap { folder in
            [folder] + collectFolders(in: folder.id)
        }
    }
}
