import Foundation
import Testing
@testable import Enchron

struct LocalDataSourceAdapterTests {
    @Test("local adapter navigates a real nested folder without copying media")
    func nestedFolderNavigation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "enchron-local-source-\(UUID().uuidString)", directoryHint: .isDirectory)
        let season = root.appending(path: "Season 1", directoryHint: .isDirectory)
        let episode = season.appending(path: "Episode 01.mkv")
        let ignored = season.appending(path: "notes.txt")
        let rootMovie = root.appending(path: "Feature.mp4")
        try FileManager.default.createDirectory(at: season, withIntermediateDirectories: true)
        try Data("episode".utf8).write(to: episode)
        try Data("notes".utf8).write(to: ignored)
        try Data("feature".utf8).write(to: rootMovie)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceID = UUID()
        let adapter = LocalDataSourceAdapter()
        adapter.ownerDataSourceID = sourceID
        try await adapter.connect(
            with: .init(sourceType: .local, rootPath: root.path)
        )

        let rootFolders = try await adapter.listFolders(at: ".")
        let rootFiles = try await adapter.listContents(at: ".")
        let listedSeason = try #require(rootFolders.first)

        #expect(rootFolders.map(\.name) == ["Season 1"])
        #expect(listedSeason.dataSourceID == sourceID)
        #expect(listedSeason.url.standardizedFileURL == season.standardizedFileURL)
        #expect(rootFiles.map(\.name) == ["Feature.mp4"])

        let nestedFiles = try await adapter.listContents(at: listedSeason.path)
        let listedEpisode = try #require(nestedFiles.first)
        let resolvedEpisode = try await adapter.resolvePlayableSource(for: listedEpisode)

        #expect(nestedFiles.map(\.name) == ["Episode 01.mkv"])
        #expect(listedEpisode.url.standardizedFileURL == episode.standardizedFileURL)
        #expect(resolvedEpisode.url.standardizedFileURL == episode.standardizedFileURL)
    }

    @Test("local adapter stops serving the selected root after disconnect")
    func disconnectEndsAccess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "enchron-local-source-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = LocalDataSourceAdapter()
        try await adapter.connect(with: .init(sourceType: .local, rootPath: root.path))
        adapter.disconnect()

        await #expect(throws: LocalDataSourceError.self) {
            _ = try await adapter.listContents(at: ".")
        }
    }
}
