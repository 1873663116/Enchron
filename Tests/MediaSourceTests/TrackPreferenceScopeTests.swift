import Foundation
import MediaSource
import Testing

struct TrackPreferenceScopeTests {
    @Test("episode naming yields one series stem across release formats")
    func seriesNameIsStableAcrossFormats() {
        #expect(MediaSeriesName.parse(fileName: "Paper.S01E02.1080p.mkv") == .series("paper"))
        #expect(MediaSeriesName.parse(fileName: "Paper - 03.mkv") == .series("paper"))
        #expect(MediaSeriesName.parse(fileName: "Paper 第05集.mkv") == .series("paper"))
        #expect(MediaSeriesName.parse(fileName: "Paper 1x06.mkv") == .series("paper"))
        #expect(MediaSeriesName.parse(fileName: "[Group] Paper 07 [1080p].mkv") == .series("paper"))
        #expect(MediaSeriesName.parse(fileName: "Paper EP08.mkv") == .series("paper"))
    }

    @Test("a name without an episode marker keeps item identity")
    func nonEpisodicNamesHaveNoSeries() {
        #expect(MediaSeriesName.parse(fileName: "The Matrix.mkv") == nil)
        #expect(MediaSeriesName.parse(fileName: "Blade Runner 2049.mkv") == nil)
        #expect(MediaSeriesName.parse(fileName: "Trailer.1920x1080.mkv") == nil)
    }

    @Test("a numbered file name scopes to its directory")
    func numberedFilesScopeToDirectory() {
        #expect(MediaSeriesName.parse(fileName: "01.mkv") == .episodeOnly)
        #expect(MediaSeriesName.parse(fileName: "E02.mkv") == .episodeOnly)
        #expect(MediaSeriesName.parse(fileName: "第03集.mkv") == .episodeOnly)
    }

    @Test("one directory and stem share a scope across episodes")
    func seriesScopeIsStable() throws {
        let first = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Shows/Paper/",
            fileName: "Paper.S01E01.mkv",
            itemIdentity: nil
        ))
        let second = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Shows/Paper",
            fileName: "Paper.S01E02.mkv",
            itemIdentity: nil
        ))
        #expect(first == second)
    }

    @Test("two series in one directory keep separate scopes")
    func distinctSeriesKeepDistinctScopes() throws {
        let paper = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Shows",
            fileName: "Paper.S01E01.mkv",
            itemIdentity: nil
        ))
        let other = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Shows",
            fileName: "Other.S01E01.mkv",
            itemIdentity: nil
        ))
        #expect(paper != other)
    }

    @Test("the same stem in another directory keeps a separate scope")
    func directorySeparatesScopes() throws {
        let first = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Shows/Paper",
            fileName: "Paper.S01E01.mkv",
            itemIdentity: nil
        ))
        let second = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Archive/Paper",
            fileName: "Paper.S01E01.mkv",
            itemIdentity: nil
        ))
        #expect(first != second)
    }

    @Test("the same directory on another source keeps a separate scope")
    func sourceSeparatesScopes() throws {
        let local = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Shows/Paper",
            fileName: "Paper.S01E01.mkv",
            itemIdentity: nil
        ))
        let share = try #require(TrackPreferenceScope.file(
            sourceKey: "smb:nas",
            directoryPath: "/Shows/Paper",
            fileName: "Paper.S01E01.mkv",
            itemIdentity: nil
        ))
        #expect(local != share)
    }

    @Test("a non-episodic file falls back to its item identity")
    func nonEpisodicFileUsesItemScope() throws {
        let identity = MediaIdentity.remote(
            sourceKey: "local",
            canonicalPath: "/Movies/The Matrix.mkv"
        )
        let scope = try #require(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Movies",
            fileName: "The Matrix.mkv",
            itemIdentity: identity
        ))
        #expect(scope == TrackPreferenceScope.item(identity))
    }

    @Test("a non-episodic file without identity has no scope")
    func unscopedFileHasNoScope() {
        #expect(TrackPreferenceScope.file(
            sourceKey: "local",
            directoryPath: "/Movies",
            fileName: "The Matrix.mkv",
            itemIdentity: nil
        ) == nil)
    }

    @Test("media server series scope is keyed by provider, server and series")
    func mediaServerScopeIdentity() {
        let scope = TrackPreferenceScope.mediaServer(
            provider: "emby",
            serverID: "server",
            seriesID: "series"
        )
        #expect(scope == TrackPreferenceScope.mediaServer(
            provider: "emby",
            serverID: "server",
            seriesID: "series"
        ))
        #expect(scope != TrackPreferenceScope.mediaServer(
            provider: "emby",
            serverID: "server",
            seriesID: "other"
        ))
    }
}
