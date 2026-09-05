import CryptoKit
import Foundation
import MediaSource
import Playback
import Synchronization
import Testing
@testable import Emby

@MainActor
struct EmbyViewModelTests {
    @Test("home refreshes every time the screen appears")
    func homeRefreshOnAppear() async {
        let library = EmbyLibraryView(
            id: EmbyItemID(rawValue: "library"),
            name: "Movies",
            collectionType: "movies",
            imageTags: EmbyImageTags()
        )
        let client = ViewModelFakeEmbyClient(
            views: [library],
            resume: [movie(id: "resume")],
            nextUp: [.episode(episode(id: "next", seasonID: "season"))],
            latest: [library.id: [movie(id: "latest")]]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let viewModel = EmbyHomeViewModel(client: client, session: session)

        await viewModel.refresh()
        await viewModel.refresh()

        #expect(client.viewsCallCount == 2)
        #expect(viewModel.shelves.map { $0.title } == [
            "Continue Watching",
            "Next Up",
            "Recently Added in Movies"
        ])
    }

    @Test("library sort toggles from recently added to alphabetical")
    func librarySortToggle() async {
        let library = EmbyLibraryView(
            id: EmbyItemID(rawValue: "library"),
            name: "Movies",
            collectionType: "movies",
            imageTags: EmbyImageTags()
        )
        let client = ViewModelFakeEmbyClient(items: [movie(id: "movie")])
        let session = makeSession(client: client, server: authenticatedServer)
        let viewModel = EmbyLibraryViewModel(
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

    @Test("detail resume and restart preserve server authority and choose the server position")
    func detailPlaybackActions() async throws {
        let item = movie(id: "movie", resumeTicks: 75_000_000, mediaSourceID: "source")
        let source = playableSource(id: "source", itemID: "movie")
        let client = ViewModelFakeEmbyClient(
            itemByID: [item.metadata.id: item],
            playbackByID: [item.metadata.id: EmbyPlaybackSession(
                id: EmbyPlaySessionID(rawValue: "session"),
                mediaSources: [source]
            )]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let detail = EmbyDetailViewModel(
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
                season.metadata.id: episodes.map(EmbyLibraryItem.episode)
            ],
            playbackByID: [episodes[0].metadata.id: EmbyPlaybackSession(
                id: EmbyPlaySessionID(rawValue: "session"),
                mediaSources: [source]
            )]
        )
        let session = makeSession(client: client, server: authenticatedServer)
        let detail = EmbyDetailViewModel(
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
        let detail = EmbyDetailViewModel(
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
        let detail = EmbyDetailViewModel(
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
        let detail = EmbyDetailViewModel(
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
        let detail = EmbyDetailViewModel(
            itemID: item.metadata.id,
            client: client,
            session: makeSession(client: client, server: authenticatedServer)
        )

        await detail.refresh()

        #expect(detail.children == .none)
    }

    /// The application installs a cleartext approval handler that denies when
    /// no prompt is on screen, and these tests run inside that host. A policy of
    /// their own keeps them measuring authentication rather than the app's
    /// answer to a question nobody is there to answer.
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
        let session = EmbySessionViewModel(client: client, store: RecordingServerStore())
        let connection = EmbyConnectionViewModel(
            session: session,
            cleartextExposurePolicy: policy
        )
        connection.address = "http://example.test:8096"
        connection.username = "Cortisol"
        connection.password = "secret"

        #expect(await connection.connect() == false)
        #expect(session.server == nil)
    }

    @Test("connection persists successful authentication and surfaces failure")
    func connectionSuccessAndFailure() async {
        let successStore = RecordingServerStore()
        let successClient = ViewModelFakeEmbyClient(authenticatedServer: authenticatedServer)
        let successSession = EmbySessionViewModel(client: successClient, store: successStore)
        let success = EmbyConnectionViewModel(
            session: successSession,
            cleartextExposurePolicy: isolatedCleartextPolicy()
        )
        success.address = "example.test:8096"
        success.username = "Cortisol"
        success.password = "secret"

        #expect(await success.connect())
        #expect(successSession.server == authenticatedServer)
        #expect(successStore.savedServer == authenticatedServer)

        let failureClient = ViewModelFakeEmbyClient(
            authenticationError: EmbyError.httpStatus(401)
        )
        let failureSession = EmbySessionViewModel(
            client: failureClient,
            store: RecordingServerStore()
        )
        let failure = EmbyConnectionViewModel(
            session: failureSession,
            cleartextExposurePolicy: isolatedCleartextPolicy()
        )
        failure.address = "http://example.test:8096"
        failure.username = "Cortisol"

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
            let session = EmbySessionViewModel(
                client: client,
                store: RecordingServerStore()
            )
            let connection = EmbyConnectionViewModel(
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
        let session = EmbySessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let digest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        let receipt = try await session.embySignIn(
            identityData: identityData,
            expectedIdentityDigest: digest
        )
        #expect(receipt.schema == EmbySignInReceipt.schemaValue)
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
        let session = EmbySessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let wrongDigest = "sha256:" + String(repeating: "0", count: 64)
        await #expect(throws: EmbySignInError.self) {
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
        let session = EmbySessionViewModel(client: client, store: store)
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
        #expect(json["schema"] as? String == EmbySignInReceipt.schemaValue)
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
        let session = EmbySessionViewModel(client: client, store: store)
        let identityData = try automationIdentityData()
        let digest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        let receipt = try await session.embySignIn(
            identityData: identityData,
            expectedIdentityDigest: digest
        )
        #expect(receipt.schema == EmbySignInReceipt.schemaValue)
        #expect(store.savedServer == authenticatedServer)
    }
#endif
}

private final class ViewModelFakeEmbyClient: EmbyClientProtocol, Sendable {
    private struct State: Sendable {
        var viewsCallCount = 0
        var itemQueries: [EmbyItemQuery] = []
    }

    private let state = Mutex(State())
    private let authenticatedServer: EmbyAuthenticatedServer?
    private let authenticationError: (any Error & Sendable)?
    private let viewValues: [EmbyLibraryView]
    private let itemValues: [EmbyLibraryItem]
    private let resumeValues: [EmbyLibraryItem]
    private let nextUpValues: [EmbyLibraryItem]
    private let latestValues: [EmbyItemID: [EmbyLibraryItem]]
    private let itemByID: [EmbyItemID: EmbyLibraryItem]
    private let childrenByID: [EmbyItemID: [EmbyLibraryItem]]
    private let playbackByID: [EmbyItemID: EmbyPlaybackSession]

    init(
        authenticatedServer: EmbyAuthenticatedServer? = nil,
        authenticationError: (any Error & Sendable)? = nil,
        views: [EmbyLibraryView] = [],
        items: [EmbyLibraryItem] = [],
        resume: [EmbyLibraryItem] = [],
        nextUp: [EmbyLibraryItem] = [],
        latest: [EmbyItemID: [EmbyLibraryItem]] = [:],
        itemByID: [EmbyItemID: EmbyLibraryItem] = [:],
        childrenByID: [EmbyItemID: [EmbyLibraryItem]] = [:],
        playbackByID: [EmbyItemID: EmbyPlaybackSession] = [:]
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
    }

    var viewsCallCount: Int { state.withLock { $0.viewsCallCount } }
    var itemQueries: [EmbyItemQuery] { state.withLock { $0.itemQueries } }

    func authenticate(address: URL, username: String, password: String) async throws -> EmbyAuthenticatedServer {
        if let authenticationError { throw authenticationError }
        return authenticatedServer ?? authenticatedServerFallback
    }

    func views(on server: EmbyAuthenticatedServer) async throws -> [EmbyLibraryView] {
        state.withLock { $0.viewsCallCount += 1 }
        return viewValues
    }

    func items(
        in viewID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage {
        state.withLock { $0.itemQueries.append(query) }
        return EmbyItemPage(items: itemValues, totalRecordCount: itemValues.count)
    }

    func item(withID itemID: EmbyItemID, on server: EmbyAuthenticatedServer) async throws -> EmbyLibraryItem {
        guard let item = itemByID[itemID] else { throw EmbyError.invalidResponse }
        return item
    }

    func children(
        of parent: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage {
        let items = childrenByID[parent.metadata.id] ?? []
        return EmbyItemPage(items: items, totalRecordCount: items.count)
    }

    func resumeItems(
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage {
        EmbyItemPage(items: resumeValues, totalRecordCount: resumeValues.count)
    }

    func latestItems(
        in viewID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        limit: Int?
    ) async throws -> [EmbyLibraryItem] {
        latestValues[viewID] ?? []
    }

    func nextUp(
        on server: EmbyAuthenticatedServer,
        seriesID: EmbyItemID?,
        startIndex: Int?,
        limit: Int?
    ) async throws -> EmbyItemPage {
        EmbyItemPage(items: nextUpValues, totalRecordCount: nextUpValues.count)
    }

    func search(
        _ searchTerm: String,
        on server: EmbyAuthenticatedServer,
        query: EmbyItemQuery
    ) async throws -> EmbyItemPage {
        EmbyItemPage(items: itemValues, totalRecordCount: itemValues.count)
    }

    func specialFeatures(
        for itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer
    ) async throws -> [EmbyLibraryItem] { [] }

    func similarItems(
        to itemID: EmbyItemID,
        on server: EmbyAuthenticatedServer,
        limit: Int?
    ) async throws -> EmbyItemPage {
        EmbyItemPage(items: [], totalRecordCount: 0)
    }

    func imageURL(
        for itemID: EmbyItemID,
        type: EmbyImageType,
        tag: EmbyImageTag?,
        size: EmbyImageSize?,
        on server: EmbyAuthenticatedServer
    ) throws -> URL { URL(string: "http://example.test/image")! }

    func playbackInfo(
        for item: EmbyLibraryItem,
        on server: EmbyAuthenticatedServer
    ) async throws -> EmbyPlaybackSession {
        guard let playback = playbackByID[item.metadata.id] else {
            throw EmbyError.directPlayUnavailable(item.metadata.id)
        }
        return playback
    }

    func externalSubtitleURL(
        for stream: EmbyMediaStream,
        on server: EmbyAuthenticatedServer
    ) throws -> URL { URL(string: "http://example.test/subtitle")! }

    func sendPlayingStarted(_ report: EmbyPlaybackReport, on server: EmbyAuthenticatedServer) async throws {}
    func sendProgress(_ report: EmbyPlaybackReport, on server: EmbyAuthenticatedServer) async throws {}
    func sendStopped(_ report: EmbyPlaybackReport, on server: EmbyAuthenticatedServer) async throws {}
}

private final class RecordingServerStore: EmbyServerStoring, Sendable {
    private let value: Mutex<EmbyAuthenticatedServer?>

    init(server: EmbyAuthenticatedServer? = nil) {
        value = Mutex(server)
    }

    var savedServer: EmbyAuthenticatedServer? { value.withLock { $0 } }

    func loadServer() throws -> EmbyAuthenticatedServer? { value.withLock { $0 } }
    func saveServer(_ server: EmbyAuthenticatedServer) throws { value.withLock { $0 = server } }
    func deleteServer() throws { value.withLock { $0 = nil } }
}

@MainActor
private func makeSession(
    client: any EmbyClientProtocol,
    server: EmbyAuthenticatedServer
) -> EmbySessionViewModel {
    let store = RecordingServerStore(server: server)
    return EmbySessionViewModel(client: client, store: store)
}

private let authenticatedServer = EmbyAuthenticatedServer(
    id: EmbyServerID(rawValue: "server"),
    name: "Server",
    baseAddress: URL(string: "http://example.test:8096")!,
    accessToken: "token",
    userID: EmbyUserID(rawValue: "user")
)

private let authenticatedServerFallback = authenticatedServer

private func movie(
    id: String,
    resumeTicks: Int64 = 0,
    mediaSourceID: String? = nil
) -> EmbyLibraryItem {
    .movie(EmbyMovie(metadata: itemMetadata(
        id: id,
        resumeTicks: resumeTicks,
        mediaSourceID: mediaSourceID
    )))
}

private func seriesItem(id: String) -> EmbyLibraryItem {
    .series(EmbySeries(metadata: itemMetadata(id: id)))
}

private func boxSetItem(id: String) -> EmbyLibraryItem {
    .boxSet(EmbyBoxSet(metadata: itemMetadata(id: id)))
}

private func seasonItem(id: String, seriesID: String) -> EmbySeason {
    EmbySeason(
        metadata: itemMetadata(id: id),
        seriesID: EmbyItemID(rawValue: seriesID),
        indexNumber: 1
    )
}

private func episode(id: String, seasonID: String) -> EmbyEpisode {
    EmbyEpisode(
        metadata: itemMetadata(id: id),
        seriesID: EmbyItemID(rawValue: "series"),
        seasonID: EmbyItemID(rawValue: seasonID),
        seasonNumber: 1,
        episodeNumber: id.hasSuffix("2") ? 2 : 1
    )
}

private func itemMetadata(
    id: String,
    resumeTicks: Int64 = 0,
    mediaSourceID: String? = nil
) -> EmbyItemMetadata {
    EmbyItemMetadata(
        id: EmbyItemID(rawValue: id),
        name: id,
        imageTags: EmbyImageTags(),
        overview: nil,
        runTimeTicks: 900_000_000,
        userData: EmbyUserData(
            playbackPositionTicks: resumeTicks,
            played: false,
            unplayedItemCount: nil
        ),
        entityTag: "etag-\(id)",
        sizeInBytes: 1_000,
        mediaSources: mediaSourceID.map {
            [EmbyMediaSourceDescription(
                id: EmbyMediaSourceID(rawValue: $0),
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
    streams: [EmbyMediaStream] = []
) -> EmbyMediaSource {
    EmbyMediaSource(
        id: EmbyMediaSourceID(rawValue: id),
        displayName: "Version",
        container: "mkv",
        sizeInBytes: 1_000,
        mediaStreams: streams,
        defaultStreamIndexes: EmbyDefaultStreamIndexes(video: 0, audio: nil, subtitle: nil),
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
private func externalSubtitleStream(index: Int) -> EmbyMediaStream {
    EmbyMediaStream(
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
