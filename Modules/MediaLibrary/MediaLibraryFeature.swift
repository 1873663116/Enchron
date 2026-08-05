import Foundation
import MediaSource

@MainActor
public final class MediaLibraryFeature {
    public enum UITestDataset: String, Sendable {
        case standard
        case singleItem
        case sparseMixed
        case largeMixed
        case hierarchical
    }

    public enum SourceMode: Sendable {
        case production
        case uiTestFixture(sourceID: UUID, dataset: UITestDataset = .standard)
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
        case .uiTestFixture(let fixtureSourceID, let dataset):
            sourceID = fixtureSourceID
            localSource = FakeFileDataSource(catalog: .demo)
            initialLibrary = Self.makeUITestLibrary(
                sourceID: fixtureSourceID,
                dataset: dataset
            )
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
        resolver.resolveExternalSubtitleSources = { [weak browser] sourceID, path, reference in
            guard let browser else {
                throw MediaReferenceResolver.ResolutionError.unavailableSource
            }
            return try await browser.resolveExternalSubtitleSources(
                dataSourceID: sourceID,
                path: path,
                reference: reference
            )
        }

        self.browser = browser
        self.library = library
    }

    private static func makeUITestLibrary(
        sourceID: UUID,
        dataset: UITestDataset
    ) -> FileBrowsingDomain.MediaLibrary {
        var library = FileBrowsingDomain.MediaLibrary()

        func addReference(_ name: String, to folderID: UUID? = nil) {
            try? library.add(
                .init(
                    name: name,
                    locator: .sourceItem(
                        dataSourceID: sourceID,
                        path: "fake:///\(name)"
                    )
                ),
                to: folderID
            )
        }

        switch dataset {
        case .standard:
            ["Interstellar.mkv", "The Matrix.mkv", "Arrival.mkv"]
                .forEach { addReference($0) }
        case .singleItem:
            addReference("Only Film.mkv")
        case .sparseMixed:
            _ = try? library.createFolder(named: "Series")
            addReference("Short Film.mp4")
            addReference("Documentary.mov")
        case .largeMixed:
            for folderName in [
                "Archive",
                "Series",
                "A Very Long Library Folder Name That Must Not Change Card Geometry"
            ] {
                _ = try? library.createFolder(named: folderName)
            }
            for index in 1...18 {
                let prefix = index == 9
                    ? "A Very Long Media Title That Must Truncate Without Resizing"
                    : "Collection Item"
                addReference(String(format: "%@ %02d.mkv", prefix, index))
            }
        case .hierarchical:
            let series = try? library.createFolder(named: "Series")
            _ = try? library.createFolder(named: "Archive")
            addReference("The Matrix.mkv")
            addReference("Arrival.mkv")
            if let series {
                let season = try? library.createFolder(named: "Season 1", in: series.id)
                addReference("Series Trailer.mp4", to: series.id)
                if let season {
                    addReference("Episode 01.mkv", to: season.id)
                    addReference("Hidden Matrix Cut.mkv", to: season.id)
                }
            }
        }
        return library
    }
}
