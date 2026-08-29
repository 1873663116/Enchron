import Foundation
import Testing
@testable import Emby

#if DEBUG
@Suite("Emby accessibility evidence")
struct EmbyAccessibilityEvidenceTests {
    @MainActor
    @Test("structured evidence retains Home routes and a season transition")
    func routeAndSeasonEvidence() throws {
        let server = EmbyAuthenticatedServer(
            id: EmbyServerID(rawValue: "server-regression"),
            name: "Regression",
            baseAddress: try #require(URL(string: "http://192.0.2.10:8096")),
            accessToken: "secret-token-that-must-not-leak",
            userID: EmbyUserID(rawValue: "user-regression")
        )
        let library = EmbyLibraryView(
            id: EmbyItemID(rawValue: "library-regression"),
            name: "Regression Library",
            collectionType: "tvshows",
            imageTags: EmbyImageTags()
        )
        let series = evidenceSeries(id: "series-regression")
        let firstSeason = evidenceSeason(id: "season-1", seriesID: series.metadata.id)
        let secondSeason = evidenceSeason(id: "season-2", seriesID: series.metadata.id)
        let firstEpisode = evidenceEpisode(id: "episode-1", seasonID: firstSeason.metadata.id)
        let secondEpisode = evidenceEpisode(id: "episode-2", seasonID: secondSeason.metadata.id)
        let shelves = [
            EmbyHomeShelf(
                kind: .nextUp,
                title: "Next Up",
                items: [.episode(firstEpisode)]
            ),
            EmbyHomeShelf(
                kind: .recentlyAdded(library.id),
                title: "Recently Added",
                items: [series]
            )
        ]
        let navigation = EmbyNavigationModel(destination: .home, path: [series])
        var journal = EmbyEvidenceJournal()
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

        let evidence = EmbyAccessibilityEvidence(
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
        let zero = EmbyObservation<Int>.observed(0)
        let missing = EmbyObservation<Int>.unavailable("not-observed")

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
        let server = EmbyAuthenticatedServer(
            id: EmbyServerID(rawValue: "server"),
            name: "Server",
            baseAddress: try #require(URL(string: "http://example.test:8096")),
            accessToken: "private-token",
            userID: EmbyUserID(rawValue: "user")
        )
        let itemID = EmbyItemID(rawValue: "episode")
        let sourceID = EmbyMediaSourceID(rawValue: "source")
        let playSessionID = EmbyPlaySessionID(rawValue: "play-session")
        var journal = EmbyEvidenceJournal()
        journal.recordPreparedPlayback(EmbyPreparedPlaybackEvidence(
            serverID: server.id,
            userID: server.userID,
            itemID: itemID,
            mediaSourceID: sourceID,
            playSessionID: playSessionID,
            requestedAction: .resume,
            freshServerProgressTicks: 50_000_000,
            appliedStartTicks: 50_000_000
        ))
        let reports: [(EmbyAcceptedPlaybackReport.Event, Int64)] = [
            (EmbyAcceptedPlaybackReport.Event.started, 50_000_000),
            (.progress, 60_000_000),
            (.stopped, 70_000_000)
        ]
        for (event, position) in reports {
            journal.recordAcceptedPlaybackReport(EmbyAcceptedPlaybackReport(
                event: event,
                serverID: server.id,
                userID: server.userID,
                itemID: itemID,
                mediaSourceID: sourceID,
                playSessionID: playSessionID,
                positionTicks: position
            ))
        }

        let document = EmbyAccessibilityEvidence(
            server: server,
            navigation: EmbyNavigationModel(),
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

private func evidenceSeries(id: String) -> EmbyLibraryItem {
    .series(EmbySeries(metadata: evidenceMetadata(id: id)))
}

private func evidenceSeason(id: String, seriesID: EmbyItemID) -> EmbySeason {
    EmbySeason(
        metadata: evidenceMetadata(id: id),
        seriesID: seriesID,
        indexNumber: id.hasSuffix("2") ? 2 : 1
    )
}

private func evidenceEpisode(id: String, seasonID: EmbyItemID) -> EmbyEpisode {
    EmbyEpisode(
        metadata: evidenceMetadata(id: id),
        seriesID: EmbyItemID(rawValue: "series-regression"),
        seasonID: seasonID,
        seasonNumber: seasonID.rawValue.hasSuffix("2") ? 2 : 1,
        episodeNumber: 1
    )
}

private func evidenceMetadata(id: String) -> EmbyItemMetadata {
    EmbyItemMetadata(
        id: EmbyItemID(rawValue: id),
        name: id,
        imageTags: EmbyImageTags(),
        overview: nil,
        runTimeTicks: nil,
        userData: nil,
        entityTag: "etag-\(id)",
        sizeInBytes: nil
    )
}
#endif
