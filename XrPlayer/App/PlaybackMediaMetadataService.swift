import Foundation

public actor PlaybackMediaMetadataStore {
    private let defaults: UserDefaults
    private static let keyPrefix = "xrplayer.mediaMetadata."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadMetadata(for key: String) -> PlaybackMediaMetadata? {
        guard let data = defaults.data(forKey: Self.keyPrefix + key) else {
            return nil
        }
        return try? JSONDecoder().decode(PlaybackMediaMetadata.self, from: data)
    }

    func saveMetadata(_ metadata: PlaybackMediaMetadata, for key: String) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        defaults.set(data, forKey: Self.keyPrefix + key)
    }
}

public actor PlaybackMediaMetadataService {
    private let store: PlaybackMediaMetadataStore

    public init(store: PlaybackMediaMetadataStore = PlaybackMediaMetadataStore()) {
        self.store = store
    }

    func prepareMetadata(for request: PlaybackLaunchRequest) async -> PlaybackMediaMetadata? {
        var resolvedMetadata = request.initialMetadata

        if let key = request.fileIdentifier?.rawValue,
            let cachedMetadata = await store.loadMetadata(for: key) {
            resolvedMetadata = resolvedMetadata?.merging(with: cachedMetadata) ?? cachedMetadata
        }

        return resolvedMetadata
    }

    func recordDetectedProfile(
        _ profile: PlaybackCoreDomain.MediaProfile,
        for request: PlaybackLaunchRequest
    ) async -> PlaybackMediaMetadata {
        let metadata =
            request.initialMetadata?.updating(mediaProfile: profile)
            ?? PlaybackMediaMetadata(mediaProfile: profile)

        if let key = request.fileIdentifier?.rawValue {
            let merged = (await store.loadMetadata(for: key))?.merging(with: metadata) ?? metadata
            await store.saveMetadata(merged, for: key)
            return merged
        }

        return metadata
    }

    /// Returns the cached metadata for a given file identifier, or nil if not cached.
    /// Used by the prefetch service to skip already-detected files.
    func cachedProfile(for fileIdentifier: PersistenceDomain.FileIdentifier) async -> PlaybackMediaMetadata? {
        await store.loadMetadata(for: fileIdentifier.rawValue)
    }

    func persist(_ metadata: PlaybackMediaMetadata, for request: PlaybackLaunchRequest) async {
        guard let key = request.fileIdentifier?.rawValue else {
            return
        }
        let merged = (await store.loadMetadata(for: key))?.merging(with: metadata) ?? metadata
        await store.saveMetadata(merged, for: key)
    }
}
