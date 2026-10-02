import BluRayDisc
import Foundation
import MediaSource
@testable import MediaLibrary
import Testing

struct BluRayBrowsingTests {
    @Test("the authored multi-playlist ISO keeps its literal catalog identities and durations")
    func realMultiPlaylistCatalog() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "TestMedia/Samples/DiscImages/AVS-HD-709/HDMV-2d.iso")
        #expect(FileManager.default.fileExists(atPath: fixture.path))

        let catalog = try BluRayDisc.catalog(at: fixture)

        #expect(catalog.titles.count == 110)
        #expect(catalog.titles.first?.playlistID.rawValue == 0)
        #expect(catalog.titles.first?.durationSeconds == 0.04171111111111111)
        #expect(catalog.titles[43].playlistID.rawValue == 43)
        #expect(catalog.titles[43].durationSeconds == 1500.0402222222222)
        #expect(catalog.titles.last?.playlistID.rawValue == 109)
        #expect(catalog.titles.last?.durationSeconds == 9009.0)
        #expect(catalog.titles.filter(\.isMain).map(\.playlistID.rawValue) == [109])
    }

    @Test("the authored single-playlist ISO stays one complete title")
    func realSinglePlaylistCatalog() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(
                path: "TestMedia/Samples/DiscImages/DolbyVision-Profile7-FEL/FEL_test_for_AVS.iso"
            )
        #expect(FileManager.default.fileExists(atPath: fixture.path))

        let catalog = try BluRayDisc.catalog(at: fixture)

        #expect(catalog.titles.map(\.playlistID.rawValue) == [0])
        #expect(catalog.titles[0].durationSeconds == 119.91144444444444)
        #expect(catalog.titles[0].isMain)
    }

    @Test("playlist watch identities depend on the MPLS number")
    func playlistIdentityUsesMPLSNumber() {
        let discIdentity = MediaIdentity.remote(
            sourceKey: "webdav:https:media.example.test:443:guest",
            canonicalPath: "/Films/Feature.iso"
        )
        let discRevision = ContentRevision.directoryManifest(Data("catalog-v1".utf8))
        let disc = VersionedMediaIdentity(
            mediaIdentity: discIdentity,
            contentRevision: discRevision
        )

        let first = VersionedMediaIdentity.bluRayPlaylist(disc: disc, playlistID: 42)
        let same = VersionedMediaIdentity.bluRayPlaylist(disc: disc, playlistID: 42)
        let other = VersionedMediaIdentity.bluRayPlaylist(disc: disc, playlistID: 43)

        #expect(first == same)
        #expect(first != other)
    }

    @Test("Blu-ray title accessibility names the playlist ID and displayed duration")
    func bluRayTitleAccessibility() {
        let title = BluRayTitleItem(
            playlistID: BluRayPlaylistID(rawValue: 42),
            ordinal: 7,
            optionalName: "Bonus Feature",
            durationSeconds: 6_005.25,
            isMain: false
        )

        #expect(
            BluRayTitleAccessibility.label(for: title, durationText: "1 hr 40 min")
                == "Bonus Feature, Playlist ID 42, Duration 1 hr 40 min"
        )
    }

    @Test("ordinary list items keep their title as the accessibility label")
    func ordinaryListAccessibilityIsUnchanged() {
        let item = FileListGroup.Item.video(
            title: "Feature",
            fileSize: "1 GB",
            duration: "2 hr"
        )

        #expect(item.resolvedAccessibilityLabel == "Feature")
    }

    @Test("directory manifests follow authored control bytes and ignore title ordinals")
    func directoryManifestOracle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "enchron-manifest-\(UUID().uuidString)", directoryHint: .isDirectory)
        let playlistDirectory = root.appending(
            path: "BDMV/PLAYLIST",
            directoryHint: .isDirectory
        )
        let clipDirectory = root.appending(
            path: "BDMV/CLIPINF",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: playlistDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: clipDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let playlistURL = playlistDirectory.appending(path: "00042.mpls")
        try Data("playlist-a".utf8).write(to: playlistURL)
        try Data("clip-info".utf8).write(to: clipDirectory.appending(path: "00001.clpi"))
        let clip = BluRayClip(
            clipID: "00001",
            startTimeSeconds: 0,
            inTimeSeconds: 1,
            outTimeSeconds: 11,
            byteStart: 192,
            byteEnd: 1_920,
            packetCount: 10,
            streams: []
        )
        let firstTitle = BluRayDiscTitle(
            playlistID: BluRayPlaylistID(rawValue: 42),
            ordinal: 0,
            durationSeconds: 10,
            clips: [clip]
        )
        let reorderedTitle = BluRayDiscTitle(
            playlistID: BluRayPlaylistID(rawValue: 42),
            ordinal: 99,
            durationSeconds: 10,
            clips: [clip]
        )

        let first = await BluRayCatalogProjectionLoader.canonicalManifest(
            for: [firstTitle],
            source: .url(root)
        )
        let reordered = await BluRayCatalogProjectionLoader.canonicalManifest(
            for: [reorderedTitle],
            source: .url(root)
        )
        try Data("playlist-b".utf8).write(to: playlistURL)
        let changed = await BluRayCatalogProjectionLoader.canonicalManifest(
            for: [firstTitle],
            source: .url(root)
        )

        #expect(first == reordered)
        #expect(first != changed)
    }

    @Test("persisted references retain Blu-ray content and old references decode as files")
    func persistedReferenceContentMigration() throws {
        let reference = FileBrowsingDomain.MediaReference(
            name: "Feature.iso",
            locator: .sourceItem(dataSourceID: UUID(), path: "/Feature.iso"),
            content: .bluRayDisc
        )
        let encoded = try JSONEncoder().encode(reference)
        #expect(try JSONDecoder().decode(
            FileBrowsingDomain.MediaReference.self,
            from: encoded
        ).content == .bluRayDisc)

        var legacy = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "content")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        #expect(try JSONDecoder().decode(
            FileBrowsingDomain.MediaReference.self,
            from: legacyData
        ).content == .mediaFile)
    }

    @MainActor
    @Test("an ISO opens as a virtual folder with one card per authored playlist")
    func isoOpensAsVirtualFolder() async throws {
        let source = TestBluRayFileSource()
        let captured = CapturedPlaybackItem()
        let viewModel = makeViewModel(source: source, captured: captured) { _ in
            [
                BluRayTitleItem(
                    playlistID: BluRayPlaylistID(rawValue: 8),
                    ordinal: 0,
                    optionalName: nil,
                    durationSeconds: 6_005.25,
                    isMain: true
                ),
                BluRayTitleItem(
                    playlistID: BluRayPlaylistID(rawValue: 42),
                    ordinal: 1,
                    optionalName: "Bonus Feature",
                    durationSeconds: 602.5,
                    isMain: false
                )
            ]
        }
        let image = source.image

        await viewModel.loadFiles()
        await viewModel.openBluRayDisc(for: image)

        #expect(viewModel.currentBluRayTitles.map(\.playlistID.rawValue) == [8, 42])
        #expect(viewModel.currentBluRayTitles.map(\.durationSeconds) == [6_005.25, 602.5])
        #expect(viewModel.currentBluRayTitles.map(\.displayName) == ["Playlist 00008", "Bonus Feature"])
        #expect(viewModel.isBrowsingBluRayDisc)
        #expect(viewModel.canNavigateUp)
        #expect(viewModel.currentLevelHasSettled)

        viewModel.searchText = " 00008 "
        #expect(viewModel.displayedBluRayTitles.map(\.playlistID.rawValue) == [8])
        viewModel.searchText = "BONUS"
        #expect(viewModel.displayedBluRayTitles.map(\.playlistID.rawValue) == [42])
        viewModel.searchText = "unavailable title"
        #expect(viewModel.displayedBluRayTitles.isEmpty)
        viewModel.searchText = " "
        #expect(viewModel.displayedBluRayTitles.map(\.playlistID.rawValue) == [8, 42])
    }

    @MainActor
    @Test("selecting a title preserves the image source and typed playlist ID")
    func titleSelectionPreservesDiscSource() async throws {
        let source = TestBluRayFileSource()
        let captured = CapturedPlaybackItem()
        let viewModel = makeViewModel(source: source, captured: captured) { _ in
            [
                BluRayTitleItem(
                    playlistID: BluRayPlaylistID(rawValue: 42),
                    ordinal: 7,
                    optionalName: nil,
                    durationSeconds: 602.5,
                    isMain: false
                )
            ]
        }

        await viewModel.loadFiles()
        await viewModel.openBluRayDisc(for: source.image)
        viewModel.selectBluRayTitle(try #require(viewModel.currentBluRayTitles.first))
        let item = try #require(captured.item)

        #expect(item.url == source.image.url)
        #expect(item.selection == .bluRayPlaylist(
            BluRayPlaylistID(rawValue: 42),
            source: .url(source.image.url)
        ))
        #expect(item.displayName == "Playlist 00042")
    }

    @MainActor
    @Test("a corrupt ISO leaves the containing folder usable and reports the catalog error")
    func corruptImageLeavesParentUsable() async {
        let source = TestBluRayFileSource()
        let viewModel = makeViewModel(
            source: source,
            captured: CapturedPlaybackItem()
        ) { _ in
            throw TestDiscError.corrupt
        }

        await viewModel.loadFiles()
        await viewModel.openBluRayDisc(for: source.image)

        #expect(viewModel.isBrowsingBluRayDisc == false)
        #expect(viewModel.lastErrorMessage == "The Blu-ray disc is damaged or incomplete.")
        #expect(viewModel.files == [source.image])
    }

    @Test("local detection accepts a parent root and BDMV itself")
    func detectsParentAndBDMVSelf() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "enchron-bdmv-\(UUID().uuidString)", directoryHint: .isDirectory)
        let bdmv = root.appending(path: "BDMV", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bdmv, withIntermediateDirectories: true)
        try Data("INDX0200".utf8).write(to: bdmv.appending(path: "index.bdmv"))
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LocalDataSourceAdapter.bluRayDiscRootURL(for: root) == root)
        #expect(LocalDataSourceAdapter.bluRayDiscRootURL(for: bdmv) == bdmv)
        #expect(LocalDataSourceAdapter.bluRayDiscRootURL(
            for: root.appending(path: "ordinary", directoryHint: .isDirectory)
        ) == nil)
    }

    @MainActor
    private func makeViewModel(
        source: TestBluRayFileSource,
        captured: CapturedPlaybackItem,
        catalog: @escaping @Sendable (URL) async throws -> [BluRayTitleItem]
    ) -> FileBrowsingViewModel {
        FileBrowsingViewModel(
            localDataSource: source,
            bluRayCatalogAtURL: catalog,
            onPlayFile: { captured.item = $0 }
        )
    }
}

private enum TestDiscError: LocalizedError {
    case corrupt

    var errorDescription: String? {
        "The Blu-ray disc is damaged or incomplete."
    }
}

@MainActor
private final class CapturedPlaybackItem {
    var item: MediaPlaybackItem?
}

private nonisolated final class TestBluRayFileSource: LocalFileSource, @unchecked Sendable {
    let image = FileBrowsingDomain.MediaFile(
        name: "Feature.iso",
        sizeInBytes: 1_024,
        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
        fileExtension: "iso",
        url: URL(fileURLWithPath: "/fixture/Feature.iso")
    )

    var ownerDataSourceID = UUID()
    private(set) var connectionStatus: FileBrowsingDomain.ConnectionStatus = .connected

    func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {}
    func disconnect() {}
    func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] { [image] }
    func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] { [] }
    func listSubtitleFiles(at path: String) async throws -> [FileBrowsingDomain.MediaFile] { [] }
    func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] { [] }
    func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL { item.url }
    func resolvePlayableSource(
        for file: FileBrowsingDomain.MediaFile
    ) async throws -> ResolvedMediaSource {
        ResolvedMediaSource(url: file.url)
    }
}
