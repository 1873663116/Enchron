import Foundation
import Testing
@testable import MediaLibrary

struct ExternalSubtitleAssociationTests {
    @MainActor
    @Test("source-directory playback resolves only matching external subtitle files")
    func sourceDirectoryPlaybackResolvesMatchingExternalSubtitles() async throws {
        let catalog = FakeFileDataSource.Catalog(
            filesByPath: [
                "/": [
                    .init("Movie.mkv", gigabytes: 1, daysAgo: 1),
                    .init("Movie.srt", gigabytes: 0.001, daysAgo: 1),
                    .init("Movie.zh-CN.ass", gigabytes: 0.001, daysAgo: 1),
                    .init("Movie.forced.VTT", gigabytes: 0.001, daysAgo: 1),
                    .init("Movie2.srt", gigabytes: 0.001, daysAgo: 1),
                    .init("Movie notes.ssa", gigabytes: 0.001, daysAgo: 1),
                    .init("Other.Movie.srt", gigabytes: 0.001, daysAgo: 1),
                ],
            ],
            folderNamesByPath: [:]
        )
        let source = FakeFileDataSource(catalog: catalog)
        let viewModel = FileBrowsingViewModel(
            localDataSource: source,
            savedDataSourceStore: EmptySavedDataSourceStore(),
            onPlayFile: { _ in }
        )
        let video = try #require(
            try await source.listContents(at: "/").first { $0.name == "Movie.mkv" }
        )

        let playbackItem = try await viewModel.playbackItem(for: video)

        #expect(playbackItem.externalSubtitleSources.map(\.displayName) == [
            "Movie.forced.VTT",
            "Movie.srt",
            "Movie.zh-CN.ass",
        ])
        #expect(playbackItem.externalSubtitleSources.allSatisfy {
            $0.url.deletingLastPathComponent() == video.url.deletingLastPathComponent()
        })
    }

    @MainActor
    @Test("folder-bookmark playback keeps matching subtitle access with the media session")
    func folderBookmarkPlaybackResolvesMatchingExternalSubtitles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "enchron-sidecars-\(UUID().uuidString)", directoryHint: .isDirectory)
        let season = root.appending(path: "Season 1", directoryHint: .isDirectory)
        let video = season.appending(path: "Episode 01.mkv")
        let matchingSubtitle = season.appending(path: "Episode 01.zh-CN.srt")
        let unrelatedSubtitle = season.appending(path: "Episode 02.srt")
        try FileManager.default.createDirectory(at: season, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: video)
        try Data("subtitle".utf8).write(to: matchingSubtitle)
        try Data("unrelated".utf8).write(to: unrelatedSubtitle)
        defer { try? FileManager.default.removeItem(at: root) }

        let reference = FileBrowsingDomain.MediaReference(
            name: video.lastPathComponent,
            locator: .file(
                bookmark: try root.bookmarkData(
                    options: SecurityScopedFileReferenceResolver.bookmarkCreationOptions
                ),
                relativePath: "Season 1/Episode 01.mkv"
            )
        )
        var library = FileBrowsingDomain.MediaLibrary()
        try library.add(reference)
        var capturedItem: MediaPlaybackItem?
        let viewModel = MediaLibraryViewModel(
            store: EmptyMediaLibraryStore(),
            resolver: MediaReferenceResolver(),
            initialLibrary: library,
            onPlay: { capturedItem = $0 }
        )

        viewModel.play(reference)
        let deadline = ContinuousClock.now + .seconds(2)
        while capturedItem == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let playbackItem = try #require(capturedItem)

        #expect(playbackItem.externalSubtitleSources.map(\.displayName) == [
            "Episode 01.zh-CN.srt",
        ])
        #expect(playbackItem.externalSubtitleSources.first?.url.standardizedFileURL
            == matchingSubtitle.standardizedFileURL)
        playbackItem.accessLease?.release()
        playbackItem.externalSubtitleSources.forEach { $0.accessLease?.release() }
    }

    @MainActor
    @Test("saved source playback resolves sidecars through the source adapter")
    func savedSourcePlaybackResolvesExternalSubtitles() async throws {
        let sourceID = UUID()
        let catalog = FakeFileDataSource.Catalog(
            filesByPath: [
                "/": [
                    .init("Remote Movie.mkv", gigabytes: 1, daysAgo: 1),
                    .init("Remote Movie.en.srt", gigabytes: 0.001, daysAgo: 1),
                    .init("Remote Movie commentary.srt", gigabytes: 0.001, daysAgo: 1),
                ],
            ],
            folderNamesByPath: [:]
        )
        let source = FakeFileDataSource(ownerDataSourceID: sourceID, catalog: catalog)
        let browser = FileBrowsingViewModel(
            localDataSource: source,
            savedDataSourceStore: EmptySavedDataSourceStore(),
            localDataSourceID: sourceID,
            onPlayFile: { _ in }
        )
        let resolver = MediaReferenceResolver()
        resolver.resolveSourceItem = { sourceID, path, reference in
            try await browser.resolveSourceItem(
                dataSourceID: sourceID,
                path: path,
                reference: reference
            )
        }
        resolver.resolveExternalSubtitleSources = { sourceID, path, reference in
            try await browser.resolveExternalSubtitleSources(
                dataSourceID: sourceID,
                path: path,
                reference: reference
            )
        }
        let reference = FileBrowsingDomain.MediaReference(
            name: "Remote Movie.mkv",
            locator: .sourceItem(
                dataSourceID: sourceID,
                path: "fake://local/Remote%20Movie.mkv"
            )
        )
        var library = FileBrowsingDomain.MediaLibrary()
        try library.add(reference)
        var capturedItem: MediaPlaybackItem?
        let viewModel = MediaLibraryViewModel(
            store: EmptyMediaLibraryStore(),
            resolver: resolver,
            initialLibrary: library,
            onPlay: { capturedItem = $0 }
        )

        viewModel.play(reference)
        let deadline = ContinuousClock.now + .seconds(2)
        while capturedItem == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let playbackItem = try #require(capturedItem)

        #expect(playbackItem.externalSubtitleSources.map(\.displayName) == [
            "Remote Movie.en.srt",
        ])
    }

    @MainActor
    @Test("subtitle discovery failure remains separate from the playable media source")
    func subtitleDiscoveryFailureDoesNotRejectPlaybackItem() async throws {
        let source = FakeFileDataSource(
            failureMode: .listingFails(message: "directory unavailable")
        )
        let viewModel = FileBrowsingViewModel(
            localDataSource: source,
            savedDataSourceStore: EmptySavedDataSourceStore(),
            onPlayFile: { _ in }
        )
        let video = FileBrowsingDomain.MediaFile(
            name: "Movie.mkv",
            sizeInBytes: 1_024,
            modifiedAt: .now,
            fileExtension: "mkv",
            url: try #require(URL(string: "fake://local/Movie.mkv"))
        )

        let playbackItem = try await viewModel.playbackItem(for: video)

        #expect(playbackItem.url == video.url)
        #expect(playbackItem.externalSubtitleSources.isEmpty)
        #expect(playbackItem.externalSubtitleErrorMessage?.contains("directory unavailable") == true)
    }
}

nonisolated private final class EmptySavedDataSourceStore: SavedDataSourceRecordStoring,
    @unchecked Sendable {
    func loadSavedDataSourceRecords() -> Data? { nil }
    func saveSavedDataSourceRecords(_ data: Data?) {}
}

nonisolated private final class EmptyMediaLibraryStore: MediaLibraryStoring, @unchecked Sendable {
    func load() throws -> FileBrowsingDomain.MediaLibrary { .init() }
    func save(_ library: FileBrowsingDomain.MediaLibrary) throws {}
}
