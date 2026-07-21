@preconcurrency import AVFoundation
import Foundation
import Observation
import OSLog
import PlaybackCore
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

@MainActor
final class MediaReferenceResolver {
    enum ResolutionError: LocalizedError {
        case unavailableFile
        case unavailablePhoto
        case unavailableSource

        var errorDescription: String? {
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

    var resolveSourceItem: (@MainActor (
        UUID,
        String,
        FileBrowsingDomain.MediaReference
    ) async throws -> ResolvedPlaybackSource)?

    private let fileResolver = SecurityScopedFileReferenceResolver()
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "app.enchron", category: "PhotoResolver")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        try? fileManager.removeItem(at: Self.photoStagingRoot(fileManager: fileManager))
    }

    fileprivate func resolve(_ reference: FileBrowsingDomain.MediaReference) async throws -> ResolvedPlaybackSource {
        switch reference.locator {
        case .file(let bookmark, let relativePath):
            let resolved = try fileResolver.resolve(bookmark: bookmark, relativePath: relativePath)
            return ResolvedPlaybackSource(
                url: resolved.url,
                sourceAccess: resolved.access
            )
        case .photoAsset(let localIdentifier):
            return try await resolvePhoto(localIdentifier: localIdentifier)
        case .sourceItem(let dataSourceID, let path):
            guard let resolveSourceItem else { throw ResolutionError.unavailableSource }
            return try await resolveSourceItem(dataSourceID, path, reference)
        }
    }

    private func resolvePhoto(localIdentifier: String) async throws -> ResolvedPlaybackSource {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject else { throw ResolutionError.unavailablePhoto }
        let requestedAsset = await Self.requestOriginalAsset(SendablePHAsset(value: asset))
        guard let avAsset = requestedAsset.value else { throw ResolutionError.unavailablePhoto }
        if let urlAsset = avAsset as? AVURLAsset {
            let sourceAccess = PlaybackSourceAccess.retaining(avAsset, securityScoped: urlAsset.url)
            if (try? urlAsset.url.checkResourceIsReachable()) == true {
                logger.info("Photos source resolved as a directly readable file URL")
                return ResolvedPlaybackSource(url: urlAsset.url, sourceAccess: sourceAccess)
            }
            sourceAccess.release()
        }
        return try await stageOriginalPhoto(asset)
    }

    private func stageOriginalPhoto(_ asset: PHAsset) async throws -> ResolvedPlaybackSource {
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
        return ResolvedPlaybackSource(
            url: destination,
            sourceAccess: PlaybackSourceAccess.temporaryFile(destination)
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
final class MediaLibraryViewModel {
    private(set) var library: FileBrowsingDomain.MediaLibrary
    private(set) var currentFolderID: UUID?
    private(set) var folderPath: [UUID] = []
    var lastErrorMessage: String?
    private(set) var currentReferenceID: UUID?

    private let store: MediaLibraryStoring
    private let resolver: MediaReferenceResolver
    private let fileManager: FileManager
    private let onPlay: @MainActor (PlaybackLaunchRequest) -> Void

    init(
        store: MediaLibraryStoring = UserDefaultsMediaLibraryStore(),
        resolver: MediaReferenceResolver,
        fileManager: FileManager = .default,
        initialLibrary: FileBrowsingDomain.MediaLibrary? = nil,
        onPlay: @escaping @MainActor (PlaybackLaunchRequest) -> Void
    ) {
        self.store = store
        self.resolver = resolver
        self.fileManager = fileManager
        self.onPlay = onPlay
        if let initialLibrary {
            self.library = initialLibrary
        } else {
            self.library = (try? store.load()) ?? .init()
        }
    }

    var folders: [FileBrowsingDomain.LibraryFolder] {
        library.folders(in: currentFolderID)
    }

    var references: [FileBrowsingDomain.MediaReference] {
        library.references(in: currentFolderID)
    }

    var allFolders: [FileBrowsingDomain.LibraryFolder] {
        collectFolders(in: nil)
    }

    var currentFolderName: String {
        currentFolderID.flatMap { library.folder(id: $0)?.name } ?? "Media Library"
    }

    var canNavigateUp: Bool { !folderPath.isEmpty }

    var breadcrumbFolders: [FileBrowsingDomain.LibraryFolder] {
        (folderPath + [currentFolderID].compactMap { $0 }).compactMap { library.folder(id: $0) }
    }

    func createFolder(named name: String) {
        mutate {
            _ = try library.createFolder(named: name, in: currentFolderID)
        }
    }

    func open(_ folder: FileBrowsingDomain.LibraryFolder) {
        if let currentFolderID { folderPath.append(currentFolderID) }
        currentFolderID = folder.id
    }

    func navigateUp() {
        currentFolderID = folderPath.popLast()
    }

    func navigateToRoot() {
        currentFolderID = nil
        folderPath.removeAll()
    }

    func navigate(to folderID: UUID) {
        guard let index = breadcrumbFolders.firstIndex(where: { $0.id == folderID }) else { return }
        let ids = breadcrumbFolders.prefix(index + 1).map(\.id)
        currentFolderID = ids.last
        folderPath = Array(ids.dropLast())
    }

    func remove(_ reference: FileBrowsingDomain.MediaReference) {
        mutate { library.removeReference(reference.id) }
    }

    func rename(_ folder: FileBrowsingDomain.LibraryFolder, to name: String) {
        mutate { try library.renameFolder(folder.id, to: name) }
    }

    func remove(_ folder: FileBrowsingDomain.LibraryFolder) {
        mutate { library.removeFolder(folder.id) }
    }

    func move(_ reference: FileBrowsingDomain.MediaReference, to folderID: UUID?) {
        mutate { try library.moveReference(reference.id, to: folderID) }
    }

    func addFiles(_ urls: [URL]) {
        mutate {
            for url in urls {
                try addFile(url)
            }
        }
    }

    func addFolder(_ folderURL: URL) {
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

    func addPhotoItems(_ items: [(localIdentifier: String, name: String)]) {
        mutate {
            for item in items {
                try library.add(
                    .init(name: item.name, locator: .photoAsset(localIdentifier: item.localIdentifier)),
                    to: currentFolderID
                )
            }
        }
    }

    func addSourceFile(_ file: FileBrowsingDomain.MediaFile, dataSourceID: UUID, path: String) {
        mutate {
            try library.add(
                .init(
                    name: file.name,
                    locator: .sourceItem(dataSourceID: dataSourceID, path: path),
                    sizeInBytes: file.sizeInBytes,
                    modifiedAt: file.modifiedAt,
                    fileExtension: file.fileExtension
                ),
                to: currentFolderID
            )
        }
    }

    func play(_ reference: FileBrowsingDomain.MediaReference) {
        Task {
            do {
                let request = try await playbackRequest(for: reference)
                currentReferenceID = reference.id
                onPlay(request)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func nextPlaybackRequest() async -> PlaybackLaunchRequest? {
        guard let currentReferenceID,
              let next = library.nextReference(after: currentReferenceID) else { return nil }
        do {
            let request = try await playbackRequest(for: next)
            self.currentReferenceID = next.id
            return request
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    private func playbackRequest(for reference: FileBrowsingDomain.MediaReference) async throws -> PlaybackLaunchRequest {
        let source = try await resolver.resolve(reference)
        let identifier = PlaybackFileIdentifier.make(
            path: "media-library/\(reference.id.uuidString)",
            sizeInBytes: reference.sizeInBytes,
            serverFingerprint: nil
        )
        return PlaybackLaunchRequest(
            url: source.url,
            displayName: reference.name,
            fileIdentifier: identifier,
            initialMetadata: .init(fileSizeInBytes: reference.sizeInBytes),
            sourceAccess: source.sourceAccess
        )
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
