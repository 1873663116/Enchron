import CryptoKit
import Foundation
import MediaSource
import Playback
import Synchronization
import Testing
@testable import MediaServer

@MainActor
struct EmbyViewModelTests {
    @Test("home refreshes every time the screen appears")
    func homeRefreshOnAppear() async {
        let library = MediaServerLibraryView(
            id: MediaServerItemID(rawValue: "library"),
            name: "Movies",
            collectionType: "movies",
            imageTags: MediaServerImageTags()
        )
        let client = ViewModelFakeEmbyClient(
            views: [library],
            resume: [movie(id: "resume")],
            nextUp: [.episode(episode(id: "next", seasonID: "season"))],
            latest: [library.id: [movie(id: "latest")]]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let viewModel = MediaServerHomeViewModel(client: client, session: session)

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(client.viewsCallCount == 2)
        #expect(viewModel.shelves.map(\.kind) == [.continueWatching, .nextUp, .recentlyAdded(library.id)])
        #expect(viewModel.shelves.map { $0.items.map(\.metadata.name) } == [["resume"], ["next"], ["latest"]])
    }

    @Test("only an accepted stopped report invalidates Continue Watching")
    func acceptedStopInvalidatesContinueWatching() async throws {
        let item = movie(id: "movie", mediaSourceID: "source")
        let source = playableSource(id: "source", itemID: "movie")
        let playback = MediaServerPlaybackSession(
            id: MediaServerPlaySessionID(rawValue: "session"),
            mediaSources: [source]
        )
        let client = ViewModelFakeEmbyClient(
            itemByID: [item.metadata.id: item],
            playbackByID: [item.metadata.id: playback]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let request = try await session.playbackRequest(for: MediaServerPlaybackSelection(
            item: item,
            mediaSourceID: source.id,
            startAction: .fromBeginning
        ))
        let reporter = try #require(
            request.sessionReporter as? MediaServerPlaybackSessionReporter
        )
        let report = PlaybackSessionReport(
            positionSeconds: 30,
            isPaused: false,
            selectedAudioTrackID: nil,
            selectedSubtitleTrackID: nil
        )

        reporter.playbackStarted(report)
        reporter.playbackProgressed(report, reason: .timeUpdate)
        await reporter.waitForPendingReports()
        #expect(session.resumeCatalogRevision == 0)

        reporter.playbackStopped(report)
        await reporter.waitForPendingReports()
        #expect(session.resumeCatalogRevision == 1)

        let failingClient = ViewModelFakeEmbyClient(
            itemByID: [item.metadata.id: item],
            playbackByID: [item.metadata.id: playback],
            failStoppedReport: true
        )
        let failingSession = makeSession(
            client: failingClient,
            server: authenticatedServer
        )
        let failingRequest = try await failingSession.playbackRequest(
            for: MediaServerPlaybackSelection(
                item: item,
                mediaSourceID: source.id,
                startAction: .fromBeginning
            )
        )
        let failingReporter = try #require(
            failingRequest.sessionReporter as? MediaServerPlaybackSessionReporter
        )

        failingReporter.playbackStopped(report)
        await failingReporter.waitForPendingReports()
        #expect(failingSession.resumeCatalogRevision == 0)
    }

    @Test("library sort toggles from recently added to alphabetical")
    func librarySortToggle() async {
        let library = MediaServerLibraryView(
            id: MediaServerItemID(rawValue: "library"),
            name: "Movies",
            collectionType: "movies",
            imageTags: MediaServerImageTags()
        )
        let client = ViewModelFakeEmbyClient(items: [movie(id: "movie")])
        let session = makeSession(client: client, server: authenticatedServer)
        let viewModel = MediaServerLibraryViewModel(
            library: library,
            client: client,
            session: session
        )

        await viewModel.refresh()
        viewModel.setSort(.alphabetical)
        await viewModel.refresh()

        #expect(client.itemQueries.count == 2)
        #expect(client.itemQueries[0].sortBy == [.dateCreated])
        #expect(client.itemQueries[0].sortOrder == .descending)
        #expect(client.itemQueries[1].sortBy == [.sortName])
        #expect(client.itemQueries[1].sortOrder == .ascending)
    }

    @Test("resume decisions use current server progress instead of the displayed item", arguments: [false, true])
    func freshResumeDecision(isEpisode: Bool) async throws {
        let staleEpisode = episode(id: "episode-1", seasonID: "season-1")
        let freshEpisode = MediaServerEpisode(
            metadata: itemMetadata(id: "episode-1", resumeTicks: 1_547_000_000),
            seriesID: staleEpisode.seriesID,
            seasonID: staleEpisode.seasonID,
            seasonNumber: staleEpisode.seasonNumber,
            episodeNumber: staleEpisode.episodeNumber
        )
        let stale = isEpisode ? MediaServerLibraryItem.episode(staleEpisode) : movie(id: "movie")
        let fresh = isEpisode ? MediaServerLibraryItem.episode(freshEpisode) : movie(id: "movie", resumeTicks: 1_547_000_000)
        let client = ViewModelFakeEmbyClient(itemByID: [fresh.metadata.id: fresh])
        let session = makeSession(client: client, server: authenticatedServer)
        let detail = MediaServerDetailViewModel(itemID: stale.metadata.id, client: client, session: session, knownItem: stale)

        let selection = if isEpisode {
            try await detail.playbackSelection(for: staleEpisode)
        } else {
            try await detail.playbackSelection(startAction: .resume)
        }

        #expect(selection.resumeCandidateSeconds == 154.7)
        #expect(selection.item.metadata.id == stale.metadata.id)
    }

    @Test("detail resume and restart preserve server authority and choose the server position")
    func detailPlaybackActions() async throws {
        let item = movie(id: "movie", resumeTicks: 75_000_000, mediaSourceID: "source")
        let source = playableSource(id: "source", itemID: "movie")
        let client = ViewModelFakeEmbyClient(
            itemByID: [item.metadata.id: item],
            playbackByID: [item.metadata.id: MediaServerPlaybackSession(
                id: MediaServerPlaySessionID(rawValue: "session"),
                mediaSources: [source]
            )]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let detail = MediaServerDetailViewModel(
            itemID: item.metadata.id,
            client: client,
            session: session
        )
        await detail.refresh()

        let resumed = try await session.playbackRequest(
            for: detail.playbackSelection(startAction: .resume)
        )
        let restarted = try await session.playbackRequest(
            for: detail.playbackSelection(startAction: .fromBeginning)
        )

        #expect(resumed.viewingStateAuthority == .mediaServer)
        #expect(restarted.viewingStateAuthority == .mediaServer)
        #expect(resumed.startPositionSeconds == 7.5)
        #expect(restarted.startPositionSeconds == 0)
    }

    @Test("episode playback builds a queue that ends at the selected season")
    func episodeQueueConstruction() async throws {
        let series = seriesItem(id: "series")
        let season = seasonItem(id: "season-1", seriesID: "series")
        let episodes = [
            episode(id: "episode-1", seasonID: "season-1"),
            episode(id: "episode-2", seasonID: "season-1")
        ]
        let source = playableSource(id: "episode-source", itemID: "episode-1")
        let client = ViewModelFakeEmbyClient(
            itemByID: [
                series.metadata.id: series,
                episodes[0].metadata.id: .episode(episodes[0])
            ],
            childrenByID: [
                series.metadata.id: [.season(season)],
                season.metadata.id: episodes.map(MediaServerLibraryItem.episode)
            ],
            playbackByID: [episodes[0].metadata.id: MediaServerPlaybackSession(
                id: MediaServerPlaySessionID(rawValue: "session"),
                mediaSources: [source]
            )]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let detail = MediaServerDetailViewModel(
            itemID: series.metadata.id,
            client: client,
            session: session
        )
        await detail.refresh()

        let request = try await session.playbackRequest(
            for: detail.playbackSelection(for: episodes[0])
        )
        let queue = session.playbackQueue

        #expect(request.collectionOrigin == .mediaServer)
        #expect(queue.entries.map(\.displayName) == ["episode-1", "episode-2"])
        #expect(queue.entries.map(\.isCurrent) == [true, false])
    }

    @Test("a series browses its seasons and follows the selected one")
    func seriesChildren() async {
        let series = seriesItem(id: "series")
        let first = seasonItem(id: "season-1", seriesID: "series")
        let second = seasonItem(id: "season-2", seriesID: "series")
        let client = ViewModelFakeEmbyClient(
            itemByID: [series.metadata.id: series],
            childrenByID: [
                series.metadata.id: [.season(first), .season(second)],
                first.metadata.id: [.episode(episode(id: "episode-1", seasonID: "season-1"))],
                second.metadata.id: [.episode(episode(id: "episode-2", seasonID: "season-2"))]
            ]
        )
        let detail = MediaServerDetailViewModel(
            itemID: series.metadata.id,
            client: client,
            session: makeSession(client: client, server: authenticatedServer)
        )

        await detail.refresh()
        #expect(detail.children == .seasons(
            all: [first, second],
            selected: first.metadata.id,
            episodes: [episode(id: "episode-1", seasonID: "season-1")]
        ))

        await detail.selectSeason(second.metadata.id)
        #expect(detail.children.selectedSeasonID == second.metadata.id)
        #expect(detail.children.episodes.map(\.metadata.id.rawValue) == ["episode-2"])
    }

    @Test("a season browses its episodes without a season control")
    func seasonChildren() async {
        let season = seasonItem(id: "season-1", seriesID: "series")
        let client = ViewModelFakeEmbyClient(
            itemByID: [season.metadata.id: .season(season)],
            childrenByID: [season.metadata.id: [.episode(episode(id: "episode-1", seasonID: "season-1"))]]
        )
        let detail = MediaServerDetailViewModel(
            itemID: season.metadata.id,
            client: client,
            session: makeSession(client: client, server: authenticatedServer)
        )

        await detail.refresh()

        #expect(detail.children == .episodes([episode(id: "episode-1", seasonID: "season-1")]))
    }

    @Test("a collection browses its members")
    func collectionChildren() async {
        let collection = boxSetItem(id: "collection")
        let member = movie(id: "member")
        let client = ViewModelFakeEmbyClient(
            itemByID: [collection.metadata.id: collection],
            childrenByID: [collection.metadata.id: [member]]
        )
        let detail = MediaServerDetailViewModel(
            itemID: collection.metadata.id,
            client: client,
            session: makeSession(client: client, server: authenticatedServer)
        )

        await detail.refresh()

        #expect(detail.children == .collection([member]))
    }

    @Test("a movie browses nothing")
    func movieChildren() async {
        let item = movie(id: "movie")
        let client = ViewModelFakeEmbyClient(itemByID: [item.metadata.id: item])
        let detail = MediaServerDetailViewModel(
            itemID: item.metadata.id,
            client: client,
            session: makeSession(client: client, server: authenticatedServer)
        )

        await detail.refresh()

        #expect(detail.children == .none)
    }

    func isolatedCleartextPolicy() -> CleartextExposurePolicy {
        let suiteName = "EmbyViewModelTests.cleartext.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return CleartextExposurePolicy(defaults: defaults)
    }

    @Test("a cleartext address the wearer declines does not connect")
    func aDeclinedCleartextAddressDoesNotConnect() async {
        let policy = isolatedCleartextPolicy()
        policy.approvalHandler = { _ in false }
        let client = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let session = MediaServerSessionViewModel(client: client, store: RecordingServerStore())
        let connection = MediaServerConnectionViewModel(
            session: session,
            cleartextExposurePolicy: policy
        )
        connection.address = "http://example.test:8096"
        connection.username = "TestUser"
        connection.password = "secret"

        #expect(await connection.connect() == false)
        #expect(session.server == nil)
    }

    @Test("connection persists successful authentication and surfaces failure")
    func connectionSuccessAndFailure() async {
        let successStore = RecordingServerStore()
        let successClient = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let successSession = MediaServerSessionViewModel(client: successClient, store: successStore)
        let success = MediaServerConnectionViewModel(
            session: successSession,
            cleartextExposurePolicy: isolatedCleartextPolicy()
        )
        success.address = "example.test:8096"
        success.username = "TestUser"
        success.password = "secret"

        #expect(await success.connect())
        #expect(successSession.server == authenticatedServer)
        #expect(successStore.savedServer == authenticatedServer)

        let failureClient = ViewModelFakeEmbyClient(
            authenticationError: MediaServerError.httpStatus(401)
        )
        let failureSession = MediaServerSessionViewModel(
            client: failureClient,
            store: RecordingServerStore()
        )
        let failure = MediaServerConnectionViewModel(
            session: failureSession,
            cleartextExposurePolicy: isolatedCleartextPolicy()
        )
        failure.address = "http://example.test:8096"
        failure.username = "TestUser"

        #expect(await failure.connect() == false)
        #expect(failureSession.server == nil)
        #expect(failure.errorMessage != nil)
    }

    @Test("connection presents stable remote failure messages")
    func connectionRemoteFailureMessages() async {
        let scenarios: [(RemoteConnectionFailure, String)] = [
            (
                .credentialsRejected,
                "Credentials rejected. Check your username and password."
            ),
            (
                .requiresHTTPS,
                "This server requires HTTPS. Add https:// to the address and try again."
            ),
            (
                .serverUnreachable,
                "Server unreachable. Check the address and your network connection."
            )
        ]

        for (failure, expectedMessage) in scenarios {
            let client = ViewModelFakeEmbyClient(authenticationError: failure)
            let session = MediaServerSessionViewModel(
                client: client,
                store: RecordingServerStore()
            )
            let connection = MediaServerConnectionViewModel(
                session: session,
                cleartextExposurePolicy: isolatedCleartextPolicy()
            )
            connection.address = "http://example.test:8096"

            #expect(await connection.connect() == false)
            #expect(connection.errorMessage == expectedMessage)
        }
    }

#if DEBUG
    @Test("emby sign-in authenticates and persists when digest matches")
    func embySignInVerifiesAndPersists() async throws {
        let client = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let store = RecordingServerStore()
        let session = MediaServerSessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let digest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        let receipt = try await session.embySignIn(
            identityData: identityData,
            expectedIdentityDigest: digest
        )
        #expect(receipt.schema == MediaServerSignInReceipt.schemaValue)
        #expect(receipt.identityDigest == digest)
        #expect(receipt.serverID == authenticatedServer.id.rawValue)
        #expect(receipt.userID == authenticatedServer.userID.rawValue)
        #expect(receipt.persisted)
        #expect(store.savedServer == authenticatedServer)
        #expect(session.server == authenticatedServer)
    }
    @Test("emby sign-in rejects digest mismatch before authentication")
    func embySignInRejectsDigestMismatch() async throws {
        let client = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let store = RecordingServerStore()
        let session = MediaServerSessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let wrongDigest = "sha256:" + String(repeating: "0", count: 64)
        await #expect(throws: MediaServerSignInError.self) {
            try await session.embySignIn(
                identityData: identityData,
                expectedIdentityDigest: wrongDigest
            )
        }
        #expect(store.savedServer == nil)
        #expect(session.server == nil)
    }
    @Test("sign-in receipt has no fixture fields")
    func signInReceiptHasNoFixtureFields() async throws {
        let client = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let store = RecordingServerStore()
        let session = MediaServerSessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let digest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        let receipt = try await session.embySignIn(
            identityData: identityData,
            expectedIdentityDigest: digest
        )
        let data = try JSONEncoder().encode(receipt)
        let object = try JSONSerialization.jsonObject(with: data)
        let json = object as? [String: Any]
        #expect(json != nil)
        guard let json else { return }
        #expect(json["schema"] as? String == MediaServerSignInReceipt.schemaValue)
        #expect(json["serverID"] as? String == authenticatedServer.id.rawValue)
        #expect(json["userID"] as? String == authenticatedServer.userID.rawValue)
        #expect(json["identityDigest"] as? String == digest)
        #expect(json["persisted"] as? Bool == true)
        #expect(json["itemID"] == nil)
        #expect(json["mediaSourceID"] == nil)
        #expect(json["externalSubtitleStreamIndex"] == nil)
        #expect(json["externalSubtitleSourceID"] == nil)
    }
    @Test("sign-in ignores fixture drift and still persists")
    func signInIgnoresFixtureDrift() async throws {
        let client = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let store = RecordingServerStore()
        let session = MediaServerSessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let digest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        let receipt = try await session.embySignIn(
            identityData: identityData,
            expectedIdentityDigest: digest
        )
        #expect(receipt.schema == MediaServerSignInReceipt.schemaValue)
        #expect(store.savedServer == authenticatedServer)
    }
#endif
}

private final class ViewModelFakeEmbyClient: MediaServerClientProtocol, Sendable {
    private struct State: Sendable {
        var viewsCallCount = 0
        var itemQueries: [MediaServerItemQuery] = []
    }

    private let state = Mutex(State())
    private let authenticatedServer: MediaServerAuthenticatedServer?
    private let authenticationError: (any Error & Sendable)?
    private let viewValues: [MediaServerLibraryView]
    private let itemValues: [MediaServerLibraryItem]
    private let resumeValues: [MediaServerLibraryItem]
    private let nextUpValues: [MediaServerLibraryItem]
    private let latestValues: [MediaServerItemID: [MediaServerLibraryItem]]
    private let itemByID: [MediaServerItemID: MediaServerLibraryItem]
    private let childrenByID: [MediaServerItemID: [MediaServerLibraryItem]]
    private let playbackByID: [MediaServerItemID: MediaServerPlaybackSession]
    private let failStoppedReport: Bool

    init(
        authenticatedServer: MediaServerAuthenticatedServer? = nil,
        authenticationError: (any Error & Sendable)? = nil,
        views: [MediaServerLibraryView] = [],
        items: [MediaServerLibraryItem] = [],
        resume: [MediaServerLibraryItem] = [],
        nextUp: [MediaServerLibraryItem] = [],
        latest: [MediaServerItemID: [MediaServerLibraryItem]] = [:],
        itemByID: [MediaServerItemID: MediaServerLibraryItem] = [:],
        childrenByID: [MediaServerItemID: [MediaServerLibraryItem]] = [:],
        playbackByID: [MediaServerItemID: MediaServerPlaybackSession] = [:],
        failStoppedReport: Bool = false
    ) {
        self.authenticatedServer = authenticatedServer
        self.authenticationError = authenticationError
        viewValues = views
        itemValues = items
        resumeValues = resume
        nextUpValues = nextUp
        latestValues = latest
        self.itemByID = itemByID
        self.childrenByID = childrenByID
        self.playbackByID = playbackByID
        self.failStoppedReport = failStoppedReport
    }

    var viewsCallCount: Int { state.withLock { $0.viewsCallCount } }
    var itemQueries: [MediaServerItemQuery] { state.withLock { $0.itemQueries } }

    func authenticate(_ login: MediaServerLogin) async throws -> MediaServerAuthenticatedServer {
        if let authenticationError { throw authenticationError }
        return authenticatedServer ?? authenticatedServerFallback
    }

    func views(on server: MediaServerAuthenticatedServer) async throws -> [MediaServerLibraryView] {
        state.withLock { $0.viewsCallCount += 1 }
        return viewValues
    }

    func items(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage {
        state.withLock { $0.itemQueries.append(query) }
        return MediaServerItemPage(items: itemValues, totalRecordCount: itemValues.count)
    }

    func item(withID itemID: MediaServerItemID, on server: MediaServerAuthenticatedServer) async throws -> MediaServerLibraryItem {
        guard let item = itemByID[itemID] else { throw MediaServerError.invalidResponse }
        return item
    }

    func children(
        of parent: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage {
        let items = childrenByID[parent.metadata.id] ?? []
        return MediaServerItemPage(items: items, totalRecordCount: items.count)
    }

    func resumeItems(
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage {
        MediaServerItemPage(items: resumeValues, totalRecordCount: resumeValues.count)
    }

    func latestItems(
        in viewID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int?
    ) async throws -> [MediaServerLibraryItem] {
        latestValues[viewID] ?? []
    }

    func nextUp(
        on server: MediaServerAuthenticatedServer,
        seriesID: MediaServerItemID?,
        startIndex: Int?,
        limit: Int?
    ) async throws -> MediaServerItemPage {
        MediaServerItemPage(items: nextUpValues, totalRecordCount: nextUpValues.count)
    }

    func search(
        _ searchTerm: String,
        on server: MediaServerAuthenticatedServer,
        query: MediaServerItemQuery
    ) async throws -> MediaServerItemPage {
        MediaServerItemPage(items: itemValues, totalRecordCount: itemValues.count)
    }

    func specialFeatures(
        for itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer
    ) async throws -> [MediaServerLibraryItem] { [] }

    func similarItems(
        to itemID: MediaServerItemID,
        on server: MediaServerAuthenticatedServer,
        limit: Int?
    ) async throws -> MediaServerItemPage {
        MediaServerItemPage(items: [], totalRecordCount: 0)
    }

    func imageURL(
        for itemID: MediaServerItemID,
        type: MediaServerImageType,
        tag: MediaServerImageTag?,
        size: MediaServerImageSize?,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL { URL(string: "http://example.test/image")! }

    func playbackInfo(
        for item: MediaServerLibraryItem,
        on server: MediaServerAuthenticatedServer
    ) async throws -> MediaServerPlaybackSession {
        guard let playback = playbackByID[item.metadata.id] else {
            throw MediaServerError.directPlayUnavailable(item.metadata.id)
        }
        return playback
    }

    func externalSubtitleURL(
        for stream: MediaServerMediaStream,
        on server: MediaServerAuthenticatedServer
    ) throws -> URL { URL(string: "http://example.test/subtitle")! }

    func sendPlayingStarted(_ report: MediaServerPlaybackReport, on server: MediaServerAuthenticatedServer) async throws {}
    func sendProgress(_ report: MediaServerPlaybackReport, on server: MediaServerAuthenticatedServer) async throws {}
    func sendStopped(_ report: MediaServerPlaybackReport, on server: MediaServerAuthenticatedServer) async throws {
        if failStoppedReport {
            throw MediaServerError.httpStatus(500)
        }
    }
}

private final class RecordingServerStore: MediaServerServerStoring, Sendable {
    private let value: Mutex<MediaServerAuthenticatedServer?>

    init(server: MediaServerAuthenticatedServer? = nil) {
        value = Mutex(server)
    }

    var savedServer: MediaServerAuthenticatedServer? { value.withLock { $0 } }

    func loadServer() throws -> MediaServerAuthenticatedServer? { value.withLock { $0 } }
    func saveServer(_ server: MediaServerAuthenticatedServer) throws { value.withLock { $0 = server } }
    func deleteServer() throws { value.withLock { $0 = nil } }
}

@MainActor
private func makeSession(
    client: any MediaServerClientProtocol,
    server: MediaServerAuthenticatedServer
) -> MediaServerSessionViewModel {
    let store = RecordingServerStore(server: server)
    return MediaServerSessionViewModel(client: client, store: store)
}

private let authenticatedServer = MediaServerAuthenticatedServer(
    id: MediaServerServerID(rawValue: "server"),
    name: "Server",
    baseAddress: URL(string: "http://example.test:8096")!,
    accessToken: "token",
    userID: MediaServerUserID(rawValue: "user")
)

private let authenticatedServerFallback = authenticatedServer

private func movie(
    id: String,
    resumeTicks: Int64 = 0,
    mediaSourceID: String? = nil
) -> MediaServerLibraryItem {
    .movie(MediaServerMovie(metadata: itemMetadata(
        id: id,
        resumeTicks: resumeTicks,
        mediaSourceID: mediaSourceID
    )))
}

private func seriesItem(id: String) -> MediaServerLibraryItem {
    .series(MediaServerSeries(metadata: itemMetadata(id: id)))
}

private func boxSetItem(id: String) -> MediaServerLibraryItem {
    .boxSet(MediaServerBoxSet(metadata: itemMetadata(id: id)))
}

private func seasonItem(id: String, seriesID: String) -> MediaServerSeason {
    MediaServerSeason(
        metadata: itemMetadata(id: id),
        seriesID: MediaServerItemID(rawValue: seriesID),
        indexNumber: 1
    )
}

private func episode(id: String, seasonID: String) -> MediaServerEpisode {
    MediaServerEpisode(
        metadata: itemMetadata(id: id),
        seriesID: MediaServerItemID(rawValue: "series"),
        seasonID: MediaServerItemID(rawValue: seasonID),
        seasonNumber: 1,
        episodeNumber: id.hasSuffix("2") ? 2 : 1
    )
}

private func itemMetadata(
    id: String,
    resumeTicks: Int64 = 0,
    mediaSourceID: String? = nil
) -> MediaServerItemMetadata {
    MediaServerItemMetadata(
        id: MediaServerItemID(rawValue: id),
        name: id,
        imageTags: MediaServerImageTags(),
        overview: nil,
        runTimeTicks: 900_000_000,
        userData: MediaServerUserData(
            playbackPositionTicks: resumeTicks,
            played: false,
            unplayedItemCount: nil
        ),
        entityTag: "etag-\(id)",
        sizeInBytes: 1_000,
        mediaSources: mediaSourceID.map {
            [MediaServerMediaSourceDescription(
                id: MediaServerMediaSourceID(rawValue: $0),
                displayName: "Version",
                container: "mkv",
                mediaStreams: []
            )]
        } ?? []
    )
}

private func playableSource(
    id: String,
    itemID: String,
    streams: [MediaServerMediaStream] = []
) -> MediaServerMediaSource {
    MediaServerMediaSource(
        id: MediaServerMediaSourceID(rawValue: id),
        displayName: "Version",
        container: "mkv",
        sizeInBytes: 1_000,
        mediaStreams: streams,
        defaultStreamIndexes: MediaServerDefaultStreamIndexes(video: 0, audio: nil, subtitle: nil),
        directPlayURL: URL(string: "http://example.test/video.mkv")!,
        versionedIdentity: VersionedMediaIdentity.emby(
            serverID: "server",
            itemID: itemID,
            mediaSourceID: id,
            itemEntityTag: "etag-\(itemID)",
            sizeInBytes: 1_000,
            runTimeTicks: 900_000_000
        )
    )
}

#if DEBUG
private func externalSubtitleStream(index: Int) -> MediaServerMediaStream {
    MediaServerMediaStream(
        index: index,
        kind: .subtitle,
        codec: "subrip",
        language: "zho",
        displayTitle: "Enchron external sidecar SubRip",
        channels: nil,
        isDefault: false,
        isForced: false,
        isExternal: true,
        deliveryURL: "/Videos/episode-regression/Subtitles/\(index)/Stream.srt"
    )
}

private func automationIdentityData() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "schema": "enchron.regression.emby-runtime-identity@1",
        "address": "http://example.test:8096",
        "username": "regression-user",
        "password": "runtime-password-that-must-never-leak",
        "serverID": authenticatedServer.id.rawValue,
        "userID": authenticatedServer.userID.rawValue
    ], options: [.sortedKeys])
}
#endif
