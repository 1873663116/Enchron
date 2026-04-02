import Foundation
@preconcurrency import Photos

public enum PhotoLibraryError: LocalizedError {
    case notAuthorized
    case notConnected
    case assetNotFound
    case exportFailed
    case noVideoResource

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo Library access was denied. Please grant access in Settings."
        case .notConnected:
            return "Photo Library data source is not connected."
        case .assetNotFound:
            return "The requested photo library asset was not found."
        case .exportFailed:
            return "Failed to export video from Photo Library."
        case .noVideoResource:
            return "No video resource found for this asset."
        }
    }
}

public final class PhotoLibraryDataSourceAdapter: DataSourceConnecting, FileProviding {
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    public var ownerDataSourceID: UUID = UUID()
    private let filter = FileBrowsingDomain.FileFilter.playable

    // Cache fetched assets for resolvePlayableURL lookups by placeholder URL.
    private var assetCache: [String: PHAsset] = [:]

    public init() {}

    // MARK: - DataSourceConnecting

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        guard info.sourceType == .photoLibrary else {
            throw PhotoLibraryError.notAuthorized
        }

        connectionStatus = .connecting

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        switch status {
        case .authorized, .limited:
            connectionStatus = .connected
        default:
            connectionStatus = .failed("Access denied")
            throw PhotoLibraryError.notAuthorized
        }
    }

    public func disconnect() {
        assetCache.removeAll()
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        guard case .connected = connectionStatus else {
            throw PhotoLibraryError.notConnected
        }

        let assets: PHFetchResult<PHAsset>
        if path == "/" {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
            assets = PHAsset.fetchAssets(with: .video, options: options)
        } else {
            // path is an album localIdentifier
            let collections = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [path], options: nil
            )
            guard let collection = collections.firstObject else {
                return []
            }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
            assets = PHAsset.fetchAssetsIn(collection, options: options)
        }

        var mediaFiles: [FileBrowsingDomain.MediaFile] = []
        assetCache.removeAll()

        assets.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let videoResource = resources.first { $0.type == .video }
                ?? resources.first { $0.type == .fullSizeVideo }
                ?? resources.first

            let filename = videoResource?.originalFilename ?? "video_\(asset.localIdentifier.prefix(8))"
            let ext = (filename as NSString).pathExtension.lowercased()
            let fileSize = videoResource?.value(forKey: "fileSize") as? Int64 ?? 0

            // Use a placeholder URL with the asset's localIdentifier for later resolution.
            let placeholderString = "photos-asset://\(asset.localIdentifier)"
            guard let placeholderURL = URL(string: placeholderString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? placeholderString) else {
                return
            }

            self.assetCache[asset.localIdentifier] = asset

            let mediaFile = FileBrowsingDomain.MediaFile(
                name: filename,
                sizeInBytes: fileSize,
                modifiedAt: asset.modificationDate ?? .distantPast,
                fileExtension: ext,
                url: placeholderURL
            )
            mediaFiles.append(mediaFile)
        }

        return mediaFiles
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        guard case .connected = connectionStatus else {
            throw PhotoLibraryError.notConnected
        }

        // Only root level shows albums; nested albums are not supported.
        guard path == "/" else { return [] }

        var folders: [FileBrowsingDomain.MediaFolder] = []

        // Fetch smart albums that contain videos.
        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .any, options: nil
        )
        smartAlbums.enumerateObjects { collection, _, _ in
            let videoOptions = PHFetchOptions()
            videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            videoOptions.fetchLimit = 1
            let videoCount = PHAsset.fetchAssets(in: collection, options: videoOptions)
            guard videoCount.count > 0 else { return }

            let folder = FileBrowsingDomain.MediaFolder(
                name: collection.localizedTitle ?? "Untitled Album",
                dataSourceID: self.ownerDataSourceID,
                path: collection.localIdentifier,
                url: URL(string: "photos-album://\(collection.localIdentifier)")
                    ?? URL(fileURLWithPath: "/")
            )
            folders.append(folder)
        }

        // Fetch user-created albums that contain videos.
        let userAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        userAlbums.enumerateObjects { collection, _, _ in
            let videoOptions = PHFetchOptions()
            videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            videoOptions.fetchLimit = 1
            let videoCount = PHAsset.fetchAssets(in: collection, options: videoOptions)
            guard videoCount.count > 0 else { return }

            let folder = FileBrowsingDomain.MediaFolder(
                name: collection.localizedTitle ?? "Untitled Album",
                dataSourceID: self.ownerDataSourceID,
                path: collection.localIdentifier,
                url: URL(string: "photos-album://\(collection.localIdentifier)")
                    ?? URL(fileURLWithPath: "/")
            )
            folders.append(folder)
        }

        return folders
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        try await resolvePlayableURL(for: item)
    }

    // MARK: - FileProviding

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        let files = try await listContents(at: folder.path)
        return sort(files: files, by: sortBy)
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
        // Extract localIdentifier from the placeholder URL.
        let urlString = file.url.absoluteString
            .removingPercentEncoding ?? file.url.absoluteString
        let identifier: String
        if urlString.hasPrefix("photos-asset://") {
            identifier = String(urlString.dropFirst("photos-asset://".count))
        } else {
            throw PhotoLibraryError.assetNotFound
        }

        // Look up asset from cache or re-fetch.
        let asset: PHAsset
        if let cached = assetCache[identifier] {
            asset = cached
        } else {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            guard let fetched = result.firstObject else {
                throw PhotoLibraryError.assetNotFound
            }
            asset = fetched
        }

        // Find the video resource.
        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .video })
            ?? resources.first(where: { $0.type == .fullSizeVideo })
        else {
            throw PhotoLibraryError.noVideoResource
        }

        // Export to a temp file.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xrplayer-photos", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let filename = videoResource.originalFilename
        let destURL = tempDir.appendingPathComponent(filename)

        // If already exported, reuse.
        if FileManager.default.fileExists(atPath: destURL.path) {
            return destURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(
                for: videoResource,
                toFile: destURL,
                options: options
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: destURL)
                }
            }
        }
    }

    // MARK: - Sorting

    private func sort(
        files: [FileBrowsingDomain.MediaFile],
        by criteria: FileBrowsingDomain.SortCriteria
    ) -> [FileBrowsingDomain.MediaFile] {
        let sorted: [FileBrowsingDomain.MediaFile]

        switch criteria.key {
        case .name:
            sorted = files.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .modifiedDate:
            sorted = files.sorted { $0.modifiedAt < $1.modifiedAt }
        case .size:
            sorted = files.sorted { $0.sizeInBytes < $1.sizeInBytes }
        }

        switch criteria.order {
        case .ascending:
            return sorted
        case .descending:
            return sorted.reversed()
        }
    }
}
