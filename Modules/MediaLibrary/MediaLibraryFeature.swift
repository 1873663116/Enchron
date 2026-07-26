import Foundation
import MediaSource

@MainActor
public final class MediaLibraryFeature {
    public enum SourceMode: Sendable {
        case production
        case uiTestFixture(sourceID: UUID)
    }

    public let browser: FileBrowsingViewModel
    public let library: MediaLibraryViewModel

    public init(
        sourceMode: SourceMode = .production,
        defaultsSuiteName: String? = nil,
        viewingStateProvider: @escaping MediaViewingStateProvider = { _ in nil },
        onPlay: @escaping @MainActor (MediaPlaybackItem) -> Void
    ) {
        let defaults = defaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let sourceID: UUID
        let localSource: any LocalFileSource
        let initialLibrary: FileBrowsingDomain.MediaLibrary?

        switch sourceMode {
        case .production:
            sourceID = UUID()
            localSource = LocalDataSourceAdapter()
            initialLibrary = nil
        case .uiTestFixture(let fixtureSourceID):
            sourceID = fixtureSourceID
            localSource = FakeFileDataSource(catalog: .demo)
            initialLibrary = Self.makeUITestLibrary(sourceID: fixtureSourceID)
        }

        let resolver = MediaReferenceResolver()
        let browser = FileBrowsingViewModel(
            localDataSource: localSource,
            viewingStateProvider: viewingStateProvider,
            localDataSourceID: sourceID,
            onPlayFile: onPlay
        )
        let library = MediaLibraryViewModel(
            store: UserDefaultsMediaLibraryStore(defaults: defaults),
            resolver: resolver,
            viewingStateProvider: viewingStateProvider,
            initialLibrary: initialLibrary,
            onPlay: onPlay
        )

        resolver.resolveSourceItem = { [weak browser] sourceID, path, reference in
            guard let browser else {
                throw MediaReferenceResolver.ResolutionError.unavailableSource
            }
            return try await browser.resolveSourceItem(
                dataSourceID: sourceID,
                path: path,
                reference: reference
            )
        }

        self.browser = browser
        self.library = library
    }

    private static func makeUITestLibrary(sourceID: UUID) -> FileBrowsingDomain.MediaLibrary {
        var library = FileBrowsingDomain.MediaLibrary()
        for name in ["Interstellar.mkv", "The Matrix.mkv", "Arrival.mkv"] {
            try? library.add(
                .init(
                    name: name,
                    locator: .sourceItem(dataSourceID: sourceID, path: "fake:///\(name)")
                )
            )
        }
        return library
    }
}
