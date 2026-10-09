import Foundation
import Testing
@testable import MediaServer

#if DEBUG
@Suite("Emby accessibility evidence")
struct EmbyAccessibilityEvidenceTests {
    @MainActor
    @Test("structured evidence retains Home routes and a season transition")
    func routeAndSeasonEvidence() throws {
        let server = MediaServerAuthenticatedServer(
            id: MediaServerServerID(rawValue: "server-regression"),
            name: "Regression",
            baseAddress: try #require(URL(string: "http://192.0.2.10:8096")),
            accessToken: "secret-token-that-must-not-leak",
            userID: MediaServerUserID(rawValue: "user-regression")
        )
        let library = MediaServerLibraryView(
            id: MediaServerItemID(rawValue: "library-regression"),
            name: "Regression Library",
            collectionType: "tvshows",
            imageTags: MediaServerImageTags()
        )
        let series = evidenceSeries(id: "series-regression")
        let firstSeason = evidenceSeason(id: "season-1", seriesID: series.metadata.id)
        let secondSeason = evidenceSeason(id: "season-2", seriesID: series.metadata.id)
        let firstEpisode = evidenceEpisode(id: "episode-1", seasonID: firstSeason.metadata.id)
        let secondEpisode = evidenceEpisode(id: "episode-2", seasonID: secondSeason.metadata.id)
        let shelves = [
            MediaServerHomeShelf(
                kind: .nextUp,
                title: "Next Up",
                items: [.episode(firstEpisode)]
            ),
            MediaServerHomeShelf(
                kind: .recentlyAdded(library.id),
                title: "Recently Added",
                items: [series]
            )
        ]
        let navigation = MediaServerNavigationModel(destination: .home, path: [series])
        var journal = MediaServerEvidenceJournal()
        journal.recordHomeActivation(
            surface: .poster,
            cardIdentifier: "Emby-PosterCard-series-regression",
            item: series,
            resultingItemID: series.metadata.id
        )
        journal.recordHomeActivation(
            surface: .nextUp,
            cardIdentifier: "Emby-PosterCard-episode-1",
            item: .episode(firstEpisode),
            resultingItemID: firstEpisode.metadata.id
        )
        journal.recordDetail(
            item: series,
            children: .seasons(
                all: [firstSeason, secondSeason],
                selected: secondSeason.metadata.id,
                episodes: [secondEpisode]
            )
        )
        journal.recordSeasonTransition(
            seriesID: series.metadata.id,
            declaredSeasons: [firstSeason, secondSeason],
            requestedSeasonID: secondSeason.metadata.id,
            beforeSelectedSeasonID: firstSeason.metadata.id,
            beforeEpisodes: [firstEpisode],
            afterSelectedSeasonID: secondSeason.metadata.id,
            afterEpisodes: [secondEpisode]
        )

        let evidence = MediaServerAccessibilityEvidence(
            server: server,
            navigation: navigation,
            libraries: [library],
            shelves: shelves,
            homeIsLoading: false,
            homeErrorMessage: nil,
            journal: journal
        )

        #expect(evidence.document.schema == "enchron.emby.accessibility-evidence@2")
        #expect(evidence.document.account.serverID == "server-regression")
        #expect(evidence.document.account.userID == "user-regression")
        #expect(evidence.document.home.shelves.map(\.kind) == ["nextUp", "recentlyAdded"])
        #expect(evidence.document.home.activations.map(\.surface) == ["poster", "nextUp"])
        #expect(evidence.document.home.activations.map(\.resultingItemID) == [
            "series-regression",
            "episode-1"
        ])
        #expect(evidence.document.detail.value?.seriesID == "series-regression")
        #expect(evidence.document.detail.value?.declaredSeasonIDs == ["season-1", "season-2"])
        #expect(evidence.document.seasonTransitions.last?.beforeEpisodeIDs == ["episode-1"])
        #expect(evidence.document.seasonTransitions.last?.afterEpisodeIDs == ["episode-2"])
        #expect(evidence.document.fixtureDigest.status == .unavailable)
        #expect(evidence.document.localViewingStateWriteCount.status == .unavailable)
        #expect(evidence.accessibilityValue.contains("secret-token") == false)
    }

    @Test("zero and unavailable are distinct evidence states")
    func observationStates() throws {
        let zero = MediaServerObservation<Int>.observed(0)
        let missing = MediaServerObservation<Int>.unavailable("not-observed")

        #expect(zero.status == .observed)
        #expect(zero.value == 0)
        #expect(zero.reason == nil)
        #expect(missing.status == .unavailable)
        #expect(missing.value == nil)
        #expect(missing.reason == "not-observed")
        #expect(try JSONEncoder().encode(zero) != JSONEncoder().encode(missing))
    }

    @MainActor
    @Test("playback projection retains requested starts and every server-accepted report")
    func playbackProjection() throws {
        let server = MediaServerAuthenticatedServer(
            id: MediaServerServerID(rawValue: "server"),
            name: "Server",
            baseAddress: try #require(URL(string: "http://example.test:8096")),
            accessToken: "private-token",
            userID: MediaServerUserID(rawValue: "user")
        )
        let itemID = MediaServerItemID(rawValue: "episode")
        let sourceID = MediaServerMediaSourceID(rawValue: "source")
        let playSessionID = MediaServerPlaySessionID(rawValue: "play-session")
        var journal = MediaServerEvidenceJournal()
        journal.recordPreparedPlayback(MediaServerPreparedPlaybackEvidence(
            serverID: server.id,
            userID: server.userID,
            itemID: itemID,
            mediaSourceID: sourceID,
            playSessionID: playSessionID,
            requestedAction: .resume,
            freshServerProgressTicks: 50_000_000,
            appliedStartTicks: 50_000_000
        ))
        let reports: [(MediaServerAcceptedPlaybackReport.Event, Int64)] = [
            (MediaServerAcceptedPlaybackReport.Event.started, 50_000_000),
            (.progress, 60_000_000),
            (.stopped, 70_000_000)
        ]
        for (event, position) in reports {
            journal.recordAcceptedPlaybackReport(MediaServerAcceptedPlaybackReport(
                event: event,
                serverID: server.id,
                userID: server.userID,
                itemID: itemID,
                mediaSourceID: sourceID,
                playSessionID: playSessionID,
                positionTicks: position
            ))
        }

        let document = MediaServerAccessibilityEvidence(
            server: server,
            navigation: MediaServerNavigationModel(),
            libraries: [],
            shelves: [],
            homeIsLoading: false,
            homeErrorMessage: nil,
            journal: journal
        ).document

        #expect(document.preparedPlaybacks.map(\.requestedAction) == ["resume"])
        #expect(document.preparedPlaybacks.map(\.freshServerProgressTicks.value) == [50_000_000])
        #expect(document.preparedPlaybacks.map(\.appliedStartTicks) == [50_000_000])
        #expect(document.playbackSessions.first?.acceptedReports.map(\.event) == [
            "started",
            "progress",
            "stopped"
        ])
        #expect(document.playbackSessions.first?.acceptedReports.map(\.positionTicks) == [
            50_000_000,
            60_000_000,
            70_000_000
        ])
        #expect(document.playbackSessions.first?.latestPositionTicks == 70_000_000)
        #expect(document.playbackSessions.first?.serverReadbackProgressTicks.status == .unavailable)
    }

}

private func evidenceSeries(id: String) -> MediaServerLibraryItem {
    .series(MediaServerSeries(metadata: evidenceMetadata(id: id)))
}

private func evidenceSeason(id: String, seriesID: MediaServerItemID) -> MediaServerSeason {
    MediaServerSeason(
        metadata: evidenceMetadata(id: id),
        seriesID: seriesID,
        indexNumber: id.hasSuffix("2") ? 2 : 1
    )
}

private func evidenceEpisode(id: String, seasonID: MediaServerItemID) -> MediaServerEpisode {
    MediaServerEpisode(
        metadata: evidenceMetadata(id: id),
        seriesID: MediaServerItemID(rawValue: "series-regression"),
        seasonID: seasonID,
        seasonNumber: seasonID.rawValue.hasSuffix("2") ? 2 : 1,
        episodeNumber: 1
    )
}

private func evidenceMetadata(id: String) -> MediaServerItemMetadata {
    MediaServerItemMetadata(
        id: MediaServerItemID(rawValue: id),
        name: id,
        imageTags: MediaServerImageTags(),
        overview: nil,
        runTimeTicks: nil,
        userData: nil,
        entityTag: "etag-\(id)",
        sizeInBytes: nil
    )
}
#endif
