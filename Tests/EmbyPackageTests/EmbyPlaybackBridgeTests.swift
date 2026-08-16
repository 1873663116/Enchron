import Foundation
import MediaSource
import PlaybackFeature
import Synchronization
import Testing
@testable import Emby

struct EmbyPlaybackBridgeTests {
    @Test("playback requests use fresh server state and the selected direct-play source")
    func requestConstruction() async throws {
        let item = movie(id: "movie", resumeTicks: 50_000_000)
        let firstSource = mediaSource(id: "source-1", container: "mp4")
        let selectedSource = mediaSource(
            id: "source-2",
            container: "mkv",
            streams: [
                mediaStream(index: 3, kind: .subtitle, external: false),
                mediaStream(index: 4, kind: .subtitle, external: true, deliveryURL: "/subtitle/4"),
            ]
        )
        let client = FakeEmbyClient(
            items: [item.metadata.id: item],
            playback: [item.metadata.id: EmbyPlaybackSession(
                id: EmbyPlaySessionID(rawValue: "play-session"),
                mediaSources: [firstSource, selectedSource]
            )]
        )
        let bridge = EmbyPlaybackBridge(client: client, server: server)

        let resumed = try await bridge.request(for: EmbyPlaybackSelection(
            item: item,
            mediaSourceID: selectedSource.id,
            startAction: .resume
        ))
        let restarted = try await bridge.request(for: EmbyPlaybackSelection(
            item: item,
            mediaSourceID: selectedSource.id,
            startAction: .fromBeginning
        ))

        #expect(resumed.viewingStateAuthority == .mediaServer)
        #expect(resumed.startPositionSeconds == 5)
        #expect(restarted.startPositionSeconds == 0)
        #expect(resumed.url.scheme == "http")
        #expect(resumed.url.host == "127.0.0.1")
        #expect(resumed.source.byteStreamHandle != nil)
        #expect(resumed.url != selectedSource.directPlayURL)
        #expect(resumed.versionedIdentity == selectedSource.versionedIdentity)
        #expect(resumed.collectionOrigin == .standalone)
        #expect(resumed.externalSubtitleSources.map(\.id) == ["emby.subtitle.4"])
        #expect(resumed.externalSubtitleSources.map(\.url.host) == ["127.0.0.1"])
        #expect(resumed.externalSubtitleSources.allSatisfy { $0.byteStreamHandle != nil })
    }

    @Test("the reporter preserves callback order and maps runtime track IDs")
    func orderedReporting() async throws {
        let client = FakeEmbyClient()
        let reporter = EmbyPlaybackSessionReporter(
            client: client,
            server: server,
            itemID: EmbyItemID(rawValue: "movie"),
            mediaSourceID: EmbyMediaSourceID(rawValue: "source"),
            playSessionID: EmbyPlaySessionID(rawValue: "session"),
            externalSubtitleStreamIndexBySourceID: ["emby.subtitle.4": 4]
        )

        reporter.playbackStarted(PlaybackSessionReport(
            positionSeconds: 1.25,
            isPaused: false,
            selectedAudioTrackID: "2",
            selectedSubtitleTrackID: "ffmpeg.subtitle.3"
        ))
        reporter.playbackProgressed(PlaybackSessionReport(
            positionSeconds: 2,
            isPaused: true,
            selectedAudioTrackID: "2",
            selectedSubtitleTrackID: "external.subtitle.emby.subtitle.4.0"
        ))
        reporter.playbackStopped(PlaybackSessionReport(
            positionSeconds: 3,
            isPaused: false,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil
        ))
        await reporter.waitForPendingReports()

        let reports = client.reports
        #expect(reports.map(\.event) == [.started, .progress, .stopped])
        #expect(reports.map(\.report.positionTicks) == [12_500_000, 20_000_000, 30_000_000])
        #expect(reports[0].report.audioStreamIndex == 2)
        #expect(reports[0].report.subtitleStreamIndex == 3)
        #expect(reports[1].report.subtitleStreamIndex == 4)
        #expect(reports[1].report.isPaused)
    }

    @Test("the UUID queue stays inside one season")
    func seasonQueue() async throws {
        let episodes = (1...3).map { episode(number: $0) }
        let items = Dictionary(uniqueKeysWithValues: episodes.map {
            ($0.metadata.id, EmbyLibraryItem.episode($0))
        })
        let playback = Dictionary(uniqueKeysWithValues: episodes.map {
            ($0.metadata.id, EmbyPlaybackSession(
                id: EmbyPlaySessionID(rawValue: "session-\($0.episodeNumber!)"),
                mediaSources: [mediaSource(id: "source", container: "mkv")]
            ))
        })
        let bridge = EmbyPlaybackBridge(
            client: FakeEmbyClient(items: items, playback: playback),
            server: server
        )

        let initial = try await bridge.request(for: EmbyPlaybackSelection(
            episode: episodes[1],
            mediaSourceID: EmbyMediaSourceID(rawValue: "source"),
            startAction: .resume,
            seasonEpisodes: episodes
        ))
        let initialSnapshot = await bridge.queueSnapshot
        let next = await bridge.nextRequest()
        let end = await bridge.nextRequest()
        let selected = await bridge.request(for: initialSnapshot.entries[0].id)
        let selectedSnapshot = await bridge.queueSnapshot

        #expect(initial.collectionOrigin == .mediaServer)
        #expect(initialSnapshot.entries.count == 3)
        #expect(initialSnapshot.entries.map(\.isCurrent) == [false, true, false])
        #expect(next?.displayName == "Episode 3")
        #expect(end == nil)
        #expect(selected?.displayName == "Episode 1")
        #expect(selectedSnapshot.entries.map(\.isCurrent) == [true, false, false])
    }
}

private enum FakeReportEvent: Equatable, Sendable {
    case started
    case progress
    case stopped
}

private struct FakeReport: Equatable, Sendable {
    let event: FakeReportEvent
    let report: EmbyPlaybackReport
}

private final class FakeEmbyClient: EmbyClientProtocol, @unchecked Sendable {
    private let itemsByID: [EmbyItemID: EmbyLibraryItem]
    private let playbackByID: [EmbyItemID: EmbyPlaybackSession]
    private let recordedReports = Mutex<[FakeReport]>([])

    init(
        items: [EmbyItemID: EmbyLibraryItem] = [:],
        playback: [EmbyItemID: EmbyPlaybackSession] = [:]
    ) {
        itemsByID = items
        playbackByID = playback
    }

    var reports: [FakeReport] { recordedReports.withLock { $0 } }

    func authenticate(address: URL, username: String, password: String) async throws -> EmbyAuthenticatedServer {
        throw FakeEmbyError.unexpected
    }

    func views(on server: EmbyAuthenticatedServer) async throws -> [EmbyLibraryView] {
        throw FakeEmbyError.unexpected
    }

    func items(in viewID: EmbyItemID, on server: EmbyAuthenticatedServer, query: EmbyItemQuery) async throws -> EmbyItemPage {
        throw FakeEmbyError.unexpected
    }

    func item(withID itemID: EmbyItemID, on server: EmbyAuthenticatedServer) async throws -> EmbyLibraryItem {
        guard let item = itemsByID[itemID] else { throw FakeEmbyError.unexpected }
        return item
    }

    func children(of parent: EmbyLibraryItem, on server: EmbyAuthenticatedServer, query: EmbyItemQuery) async throws -> EmbyItemPage {
        throw FakeEmbyError.unexpected
    }

    func resumeItems(on server: EmbyAuthenticatedServer, query: EmbyItemQuery) async throws -> EmbyItemPage {
        throw FakeEmbyError.unexpected
    }

    func nextUp(on server: EmbyAuthenticatedServer, seriesID: EmbyItemID?, startIndex: Int?, limit: Int?) async throws -> EmbyItemPage {
        throw FakeEmbyError.unexpected
    }

    func search(_ searchTerm: String, on server: EmbyAuthenticatedServer, query: EmbyItemQuery) async throws -> EmbyItemPage {
        throw FakeEmbyError.unexpected
    }

    func imageURL(for itemID: EmbyItemID, type: EmbyImageType, tag: EmbyImageTag?, size: EmbyImageSize?, on server: EmbyAuthenticatedServer) throws -> URL {
        throw FakeEmbyError.unexpected
    }

    func playbackInfo(for item: EmbyLibraryItem, on server: EmbyAuthenticatedServer) async throws -> EmbyPlaybackSession {
        guard let playback = playbackByID[item.metadata.id] else { throw FakeEmbyError.unexpected }
        return playback
    }

    func externalSubtitleURL(for stream: EmbyMediaStream, on server: EmbyAuthenticatedServer) throws -> URL {
        guard let deliveryURL = stream.deliveryURL else { throw FakeEmbyError.unexpected }
        return URL(string: "http://example.test/emby\(deliveryURL)?api_key=token")!
    }

    func sendPlayingStarted(_ report: EmbyPlaybackReport, on server: EmbyAuthenticatedServer) async throws {
        recordedReports.withLock { $0.append(FakeReport(event: .started, report: report)) }
    }

    func sendProgress(_ report: EmbyPlaybackReport, on server: EmbyAuthenticatedServer) async throws {
        recordedReports.withLock { $0.append(FakeReport(event: .progress, report: report)) }
    }

    func sendStopped(_ report: EmbyPlaybackReport, on server: EmbyAuthenticatedServer) async throws {
        recordedReports.withLock { $0.append(FakeReport(event: .stopped, report: report)) }
    }
}

private enum FakeEmbyError: Error {
    case unexpected
}

private let server = EmbyAuthenticatedServer(
    id: EmbyServerID(rawValue: "server"),
    name: "Server",
    baseAddress: URL(string: "http://example.test")!,
    accessToken: "token",
    userID: EmbyUserID(rawValue: "user")
)

private func movie(id: String, resumeTicks: Int64) -> EmbyLibraryItem {
    .movie(EmbyMovie(metadata: metadata(
        id: id,
        name: "Movie",
        resumeTicks: resumeTicks,
        entityTag: "etag-\(id)"
    )))
}

private func episode(number: Int) -> EmbyEpisode {
    EmbyEpisode(
        metadata: metadata(
            id: "episode-\(number)",
            name: "Episode \(number)",
            resumeTicks: Int64(number) * 10_000_000,
            entityTag: "etag-\(number)"
        ),
        seriesID: EmbyItemID(rawValue: "series"),
        seasonID: EmbyItemID(rawValue: "season"),
        seasonNumber: 1,
        episodeNumber: number
    )
}

private func metadata(
    id: String,
    name: String,
    resumeTicks: Int64,
    entityTag: String
) -> EmbyItemMetadata {
    EmbyItemMetadata(
        id: EmbyItemID(rawValue: id),
        name: name,
        imageTags: EmbyImageTags(),
        overview: nil,
        runTimeTicks: 900_000_000,
        userData: EmbyUserData(
            playbackPositionTicks: resumeTicks,
            played: false,
            unplayedItemCount: nil
        ),
        entityTag: entityTag,
        sizeInBytes: 1_000
    )
}

private func mediaSource(
    id: String,
    container: String,
    streams: [EmbyMediaStream] = []
) -> EmbyMediaSource {
    EmbyMediaSource(
        id: EmbyMediaSourceID(rawValue: id),
        displayName: id,
        container: container,
        sizeInBytes: 1_000,
        mediaStreams: streams,
        defaultStreamIndexes: EmbyDefaultStreamIndexes(video: 0, audio: 1, subtitle: nil),
        directPlayURL: URL(string: "http://example.test/video/\(id).\(container)")!,
        versionedIdentity: VersionedMediaIdentity.emby(
            serverID: "server",
            itemID: "movie",
            mediaSourceID: id,
            itemEntityTag: "etag",
            sizeInBytes: 1_000,
            runTimeTicks: nil
        )
    )
}

private func mediaStream(
    index: Int,
    kind: EmbyMediaStreamKind,
    external: Bool,
    deliveryURL: String? = nil
) -> EmbyMediaStream {
    EmbyMediaStream(
        index: index,
        kind: kind,
        codec: "srt",
        language: "eng",
        displayTitle: "English",
        channels: nil,
        isDefault: false,
        isForced: false,
        isExternal: external,
        deliveryURL: deliveryURL
    )
}
