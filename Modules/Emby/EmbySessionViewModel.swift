import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import MediaSource
import Observation
import Playback

#if DEBUG
public struct EmbyAutomationFixtureExpectation: Equatable, Sendable {
    public let itemID: EmbyItemID
    public let mediaSourceID: EmbyMediaSourceID
    public let externalSubtitleStreamIndex: Int

    public init(
        itemID: EmbyItemID,
        mediaSourceID: EmbyMediaSourceID,
        externalSubtitleStreamIndex: Int
    ) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.externalSubtitleStreamIndex = externalSubtitleStreamIndex
    }
}

public struct EmbyAutomationAccountPreparationReceipt: Codable, Equatable, Sendable {
    public static let schemaValue = "enchron.regression.emby-account-preparation@1"

    public let schema: String
    public let identityDigest: String
    public let serverID: String
    public let userID: String
    public let itemID: String
    public let mediaSourceID: String
    public let externalSubtitleStreamIndex: Int
    public let externalSubtitleSourceID: String
    public let persisted: Bool

    init(
        identityDigest: String,
        server: EmbyAuthenticatedServer,
        fixture: EmbyAutomationFixtureExpectation
    ) {
        schema = Self.schemaValue
        self.identityDigest = identityDigest
        serverID = server.id.rawValue
        userID = server.userID.rawValue
        itemID = fixture.itemID.rawValue
        mediaSourceID = fixture.mediaSourceID.rawValue
        externalSubtitleStreamIndex = fixture.externalSubtitleStreamIndex
        externalSubtitleSourceID = EmbyPlaybackBridge.externalSubtitleSourceID(
            for: fixture.externalSubtitleStreamIndex
        )
        persisted = true
    }
}

public enum EmbyAutomationAccountPreparationError: Error, LocalizedError, Sendable {
    case identityDigestMismatch
    case invalidIdentity
    case authenticatedIdentityMismatch
    case fixtureItemMismatch
    case mediaSourceMismatch
    case externalSubtitleMismatch

    public var errorDescription: String? {
        switch self {
        case .identityDigestMismatch:
            "The Emby runtime identity digest did not match."
        case .invalidIdentity:
            "The Emby runtime identity document is invalid."
        case .authenticatedIdentityMismatch:
            "The authenticated Emby identity did not match the fixture authority."
        case .fixtureItemMismatch:
            "The authenticated Emby fixture item did not match."
        case .mediaSourceMismatch:
            "The authenticated Emby fixture media source did not match."
        case .externalSubtitleMismatch:
            "The authenticated Emby external subtitle stream did not match."
        }
    }
}

private struct EmbyAutomationRuntimeIdentity: Decodable {
    static let schemaValue = "enchron.regression.emby-runtime-identity@1"
    static let keys: Set<String> = [
        "schema", "address", "username", "password", "serverID", "userID"
    ]

    let schema: String
    let address: String
    let username: String
    let password: String
    let serverID: String
    let userID: String
}

public struct EmbyObservation<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case observed
        case unavailable
        case notApplicable
    }

    public let status: Status
    public let value: Value?
    public let reason: String?

    public static func observed(_ value: Value) -> Self {
        Self(status: .observed, value: value, reason: nil)
    }

    public static func unavailable(_ reason: String) -> Self {
        Self(status: .unavailable, value: nil, reason: reason)
    }

    public static func notApplicable(_ reason: String) -> Self {
        Self(status: .notApplicable, value: nil, reason: reason)
    }
}

public enum EmbyHomeCardSurface: String, Codable, Equatable, Sendable {
    case poster
    case nextUp
    case continueWatching
}

public struct EmbyHomeActivationEvidence: Codable, Equatable, Sendable {
    public let surface: String
    public let cardIdentifier: String
    public let itemID: String
    public let itemKind: String
    public let resultingItemID: String
}

public struct EmbyDetailEvidence: Codable, Equatable, Sendable {
    public let itemID: String
    public let itemKind: String
    public let seriesID: String?
    public let declaredSeasonIDs: [String]
    public let selectedSeasonID: String?
    public let episodeIDs: [String]
    public let playbackActionIDs: [String]
}

public struct EmbySeasonTransitionEvidence: Codable, Equatable, Sendable {
    public let seriesID: String
    public let declaredSeasonIDs: [String]
    public let requestedSeasonID: String
    public let beforeSelectedSeasonID: String?
    public let beforeEpisodeIDs: [String]
    public let afterSelectedSeasonID: String?
    public let afterEpisodeIDs: [String]
}

public struct EmbyArtworkLoadRequest: Sendable, Equatable {
    public let itemID: EmbyItemID
    public let imageType: EmbyImageType
    public let imageTag: EmbyImageTag
    public let url: URL

    public init(
        itemID: EmbyItemID,
        imageType: EmbyImageType,
        imageTag: EmbyImageTag,
        url: URL
    ) {
        self.itemID = itemID
        self.imageType = imageType
        self.imageTag = imageTag
        self.url = url
    }
}

public struct EmbyArtworkNetworkEvidence: Codable, Equatable, Sendable {
    public let statusCode: Int
    public let responseDigest: String
    public let responseBytes: Int
    public let sanitizedResponseURL: EmbyObservation<String>
}

public struct EmbyArtworkPersistedEvidence: Codable, Equatable, Sendable {
    public let artworkKey: String
    public let digest: String
    public let bytes: Int
    public let width: Int
    public let height: Int
}

public struct EmbyArtworkEvidence: Codable, Equatable, Sendable {
    public let itemID: String
    public let imageType: String
    public let imageTag: String
    public let sanitizedRequestURL: String?
    public let cacheKey: String
    public let cacheHit: EmbyObservation<Bool>
    public let network: EmbyObservation<EmbyArtworkNetworkEvidence>
    public let persistedCache: EmbyObservation<EmbyArtworkPersistedEvidence>
    public let loopbackHitCount: EmbyObservation<Int>
}

public struct EmbyArtworkEvidenceLoader: Sendable {
    private let store: ArtworkStore
    private let session: URLSession

    public init(store: ArtworkStore, session: URLSession) {
        self.store = store
        self.session = session
    }

    public func load(_ request: EmbyArtworkLoadRequest) async -> EmbyArtworkEvidence {
        let key = ArtworkKey(remoteImageURL: request.url)
        let sanitizedURL = Self.sanitizedURL(for: request)
        guard let sanitizedURL else {
            return EmbyArtworkEvidence(
                itemID: request.itemID.rawValue,
                imageType: request.imageType.rawValue,
                imageTag: request.imageTag.rawValue,
                sanitizedRequestURL: nil,
                cacheKey: key.debugStorageKey,
                cacheHit: .unavailable("request-route-invalid"),
                network: .unavailable("request-route-invalid"),
                persistedCache: .unavailable("request-route-invalid"),
                loopbackHitCount: .unavailable("request-route-invalid")
            )
        }
        if store.image(for: key) != nil {
            return EmbyArtworkEvidence(
                itemID: request.itemID.rawValue,
                imageType: request.imageType.rawValue,
                imageTag: request.imageTag.rawValue,
                sanitizedRequestURL: sanitizedURL.absoluteString,
                cacheKey: key.debugStorageKey,
                cacheHit: .observed(true),
                network: .notApplicable("persisted-cache-hit"),
                persistedCache: persistedEvidence(for: key),
                loopbackHitCount: .notApplicable("no-network-request")
            )
        }
        do {
            let (data, response) = try await session.data(for: URLRequest(
                url: request.url,
                cachePolicy: .reloadIgnoringLocalCacheData
            ))
            guard let response = response as? HTTPURLResponse else {
                return failure(
                    request: request,
                    key: key,
                    sanitizedURL: sanitizedURL,
                    reason: "response-not-http"
                )
            }
            guard (200...299).contains(response.statusCode) else {
                return failure(
                    request: request,
                    key: key,
                    sanitizedURL: sanitizedURL,
                    reason: "http-status-\(response.statusCode)"
                )
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return failure(
                    request: request,
                    key: key,
                    sanitizedURL: sanitizedURL,
                    reason: "response-image-invalid"
                )
            }
            try store.store(image, for: key)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            return EmbyArtworkEvidence(
                itemID: request.itemID.rawValue,
                imageType: request.imageType.rawValue,
                imageTag: request.imageTag.rawValue,
                sanitizedRequestURL: sanitizedURL.absoluteString,
                cacheKey: key.debugStorageKey,
                cacheHit: .observed(false),
                network: .observed(EmbyArtworkNetworkEvidence(
                    statusCode: response.statusCode,
                    responseDigest: "sha256:\(digest)",
                    responseBytes: data.count,
                    sanitizedResponseURL: response.url.flatMap {
                        Self.sanitizedURL($0, matching: request)
                    }
                    .map { .observed($0.absoluteString) }
                        ?? .unavailable("response-route-cannot-be-safely-exposed")
                )),
                persistedCache: persistedEvidence(for: key),
                loopbackHitCount: .observed(Self.isLoopback(request.url) ? 1 : 0)
            )
        } catch {
            return failure(
                request: request,
                key: key,
                sanitizedURL: sanitizedURL,
                reason: "request-failed-\(Self.errorCode(error))",
                responseWasObserved: false
            )
        }
    }

    private func persistedEvidence(
        for key: ArtworkKey
    ) -> EmbyObservation<EmbyArtworkPersistedEvidence> {
        guard let identity = store.debugStoredIdentity(for: key) else {
            return .unavailable("persisted-cache-entry-missing")
        }
        return .observed(EmbyArtworkPersistedEvidence(
            artworkKey: identity.artworkKey,
            digest: identity.digest,
            bytes: identity.bytes,
            width: identity.width,
            height: identity.height
        ))
    }

    private func failure(
        request: EmbyArtworkLoadRequest,
        key: ArtworkKey,
        sanitizedURL: URL,
        reason: String,
        responseWasObserved: Bool = true
    ) -> EmbyArtworkEvidence {
        EmbyArtworkEvidence(
            itemID: request.itemID.rawValue,
            imageType: request.imageType.rawValue,
            imageTag: request.imageTag.rawValue,
            sanitizedRequestURL: sanitizedURL.absoluteString,
            cacheKey: key.debugStorageKey,
            cacheHit: .observed(false),
            network: .unavailable(reason),
            persistedCache: .unavailable("network-load-did-not-persist"),
            loopbackHitCount: Self.isLoopback(request.url) && responseWasObserved == false
                ? .unavailable("loopback-request-arrival-not-observed")
                : .observed(Self.isLoopback(request.url) ? 1 : 0)
        )
    }

    private static func sanitizedURL(for request: EmbyArtworkLoadRequest) -> URL? {
        sanitizedURL(request.url, matching: request)
    }

    private static func sanitizedURL(
        _ url: URL,
        matching request: EmbyArtworkLoadRequest
    ) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "http" || components.scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              components.path == "/Items/\(request.itemID.rawValue)/Images/\(request.imageType.rawValue)" else {
            return nil
        }
        let publicNames: Set<String> = ["Tag", "MaxWidth", "MaxHeight"]
        components.queryItems = components.queryItems?.filter { publicNames.contains($0.name) }
        guard components.queryItems?.first(where: { $0.name == "Tag" })?.value
                == request.imageTag.rawValue else {
            return nil
        }
        return components.url
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func errorCode(_ error: Error) -> String {
        if let error = error as? URLError { return "url-\(error.code.rawValue)" }
        if error is ArtworkStore.StoreError { return "artwork-store" }
        return "unknown"
    }
}

public struct EmbyEvidenceJournal: Equatable, Sendable {
    private static let retainedEntryLimit = 64

    public private(set) var homeActivations: [EmbyHomeActivationEvidence] = []
    public private(set) var detail: EmbyDetailEvidence?
    public private(set) var seasonTransitions: [EmbySeasonTransitionEvidence] = []
    public private(set) var preparedPlaybacks: [EmbyPreparedPlaybackEvidence] = []
    public private(set) var playbackSessions: [EmbyPlaybackEvidence] = []
    public private(set) var artworkLoads: [EmbyArtworkEvidence] = []

    public init() {}

    public mutating func recordHomeActivation(
        surface: EmbyHomeCardSurface,
        cardIdentifier: String,
        item: EmbyLibraryItem,
        resultingItemID: EmbyItemID
    ) {
        homeActivations.append(EmbyHomeActivationEvidence(
            surface: surface.rawValue,
            cardIdentifier: cardIdentifier,
            itemID: item.metadata.id.rawValue,
            itemKind: Self.kind(of: item),
            resultingItemID: resultingItemID.rawValue
        ))
        trim(&homeActivations)
    }

    public mutating func recordDetail(item: EmbyLibraryItem, children: EmbyDetailChildren) {
        let seasons: [EmbySeason]
        let selectedSeasonID: EmbyItemID?
        let episodes: [EmbyEpisode]
        switch children {
        case .seasons(let all, let selected, let shown):
            seasons = all
            selectedSeasonID = selected
            episodes = shown
        case .episodes(let shown):
            seasons = []
            selectedSeasonID = item.season?.metadata.id
            episodes = shown
        case .none, .collection:
            seasons = []
            selectedSeasonID = nil
            episodes = []
        }
        let seriesID: EmbyItemID? = switch item {
        case .series: item.metadata.id
        case .season(let season): season.seriesID
        case .episode(let episode): episode.seriesID
        case .movie, .boxSet: nil
        }
        let hasResume = (item.metadata.userData?.playbackPositionTicks ?? 0) > 0
        detail = EmbyDetailEvidence(
            itemID: item.metadata.id.rawValue,
            itemKind: Self.kind(of: item),
            seriesID: seriesID?.rawValue,
            declaredSeasonIDs: seasons.map { $0.metadata.id.rawValue },
            selectedSeasonID: selectedSeasonID?.rawValue,
            episodeIDs: episodes.map { $0.metadata.id.rawValue },
            playbackActionIDs: hasResume
                ? ["Emby-Detail-Resume", "Emby-Detail-PlayFromBeginning"]
                : ["Emby-Detail-PlayFromBeginning"]
        )
    }

    public mutating func recordSeasonTransition(
        seriesID: EmbyItemID,
        declaredSeasons: [EmbySeason],
        requestedSeasonID: EmbyItemID,
        beforeSelectedSeasonID: EmbyItemID?,
        beforeEpisodes: [EmbyEpisode],
        afterSelectedSeasonID: EmbyItemID?,
        afterEpisodes: [EmbyEpisode]
    ) {
        seasonTransitions.append(EmbySeasonTransitionEvidence(
            seriesID: seriesID.rawValue,
            declaredSeasonIDs: declaredSeasons.map { $0.metadata.id.rawValue },
            requestedSeasonID: requestedSeasonID.rawValue,
            beforeSelectedSeasonID: beforeSelectedSeasonID?.rawValue,
            beforeEpisodeIDs: beforeEpisodes.map { $0.metadata.id.rawValue },
            afterSelectedSeasonID: afterSelectedSeasonID?.rawValue,
            afterEpisodeIDs: afterEpisodes.map { $0.metadata.id.rawValue }
        ))
        trim(&seasonTransitions)
    }

    public mutating func recordPreparedPlayback(_ evidence: EmbyPreparedPlaybackEvidence) {
        preparedPlaybacks.append(evidence)
        trim(&preparedPlaybacks)
    }

    public mutating func recordAcceptedPlaybackReport(_ report: EmbyAcceptedPlaybackReport) {
        if let index = playbackSessions.firstIndex(where: {
            $0.serverID == report.serverID
                && $0.userID == report.userID
                && $0.itemID == report.itemID
                && $0.mediaSourceID == report.mediaSourceID
                && $0.playSessionID == report.playSessionID
        }) {
            playbackSessions[index].record(report)
        } else {
            playbackSessions.append(EmbyPlaybackEvidence(report: report))
            trim(&playbackSessions)
        }
    }

    public mutating func recordArtwork(_ evidence: EmbyArtworkEvidence) {
        artworkLoads.append(evidence)
        trim(&artworkLoads)
    }

    private static func kind(of item: EmbyLibraryItem) -> String {
        switch item {
        case .movie: "movie"
        case .series: "series"
        case .season: "season"
        case .episode: "episode"
        case .boxSet: "boxSet"
        }
    }

    private func trim<Element>(_ values: inout [Element]) {
        if values.count > Self.retainedEntryLimit {
            values.removeFirst(values.count - Self.retainedEntryLimit)
        }
    }
}
#endif

@MainActor
@Observable
public final class EmbySessionViewModel {
    public let client: any EmbyClientProtocol
    public let playbackBridge: EmbyPlaybackBridge
    public private(set) var server: EmbyAuthenticatedServer?
    public private(set) var persistenceErrorMessage: String?
    public private(set) var playbackQueue: PlaybackQueueSnapshot = .empty
    public private(set) var playbackEvidence: EmbyPlaybackEvidence?
#if DEBUG
    public private(set) var evidenceJournal = EmbyEvidenceJournal()
#endif

    private let store: any EmbyServerStoring
    private let navigation: EmbyNavigationModel
#if DEBUG
    private let artworkEvidenceLoader = EmbyArtworkEvidenceLoader(
        store: .shared,
        session: MediaSourceNetwork.shared.session
    )
#endif

#if DEBUG
    @ObservationIgnored public var diagnosticProbe: ((String) -> Void)?
#endif

    public init(
        client: any EmbyClientProtocol,
        store: any EmbyServerStoring = KeychainEmbyServerStore(),
        navigation: EmbyNavigationModel = EmbyNavigationModel()
    ) {
        self.client = client
        self.store = store
        self.navigation = navigation
        let loadedServer: EmbyAuthenticatedServer?
        let loadErrorMessage: String?
        do {
            loadedServer = try store.loadServer()
            loadErrorMessage = nil
        } catch {
            loadedServer = nil
            loadErrorMessage = error.localizedDescription
        }
        server = loadedServer
        persistenceErrorMessage = loadErrorMessage
        playbackBridge = EmbyPlaybackBridge(client: client, server: loadedServer)
    }

    public func connect(address: URL, username: String, password: String) async throws {
        let authenticated = try await client.authenticate(
            address: address,
            username: username,
            password: password
        )
        try await install(authenticated)
    }

#if DEBUG
    public func prepareAutomationAccount(
        identityData: Data,
        expectedIdentityDigest: String,
        fixture: EmbyAutomationFixtureExpectation
    ) async throws -> EmbyAutomationAccountPreparationReceipt {
        let actualDigest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == expectedIdentityDigest else {
            throw EmbyAutomationAccountPreparationError.identityDigestMismatch
        }
        let rawDocument: Any
        do {
            rawDocument = try JSONSerialization.jsonObject(with: identityData)
        } catch {
            throw EmbyAutomationAccountPreparationError.invalidIdentity
        }
        guard let rawIdentity = rawDocument as? [String: Any],
              Set(rawIdentity.keys) == EmbyAutomationRuntimeIdentity.keys else {
            throw EmbyAutomationAccountPreparationError.invalidIdentity
        }
        let identity: EmbyAutomationRuntimeIdentity
        do {
            identity = try JSONDecoder().decode(
                EmbyAutomationRuntimeIdentity.self,
                from: identityData
            )
        } catch {
            throw EmbyAutomationAccountPreparationError.invalidIdentity
        }
        guard identity.schema == EmbyAutomationRuntimeIdentity.schemaValue,
              identity.address.isEmpty == false,
              identity.username.isEmpty == false,
              identity.password.isEmpty == false,
              identity.serverID.isEmpty == false,
              identity.userID.isEmpty == false,
              fixture.itemID.rawValue.isEmpty == false,
              fixture.mediaSourceID.rawValue.isEmpty == false,
              fixture.externalSubtitleStreamIndex >= 0,
              let address = URL(string: identity.address),
              let addressComponents = URLComponents(
                url: address,
                resolvingAgainstBaseURL: false
              ),
              let addressScheme = addressComponents.scheme?.lowercased(),
              ["http", "https"].contains(addressScheme),
              addressComponents.host?.isEmpty == false,
              addressComponents.user == nil,
              addressComponents.password == nil,
              addressComponents.fragment == nil else {
            throw EmbyAutomationAccountPreparationError.invalidIdentity
        }
        let authenticated = try await client.authenticate(
            address: address,
            username: identity.username,
            password: identity.password
        )
        guard authenticated.id.rawValue == identity.serverID,
              authenticated.userID.rawValue == identity.userID else {
            throw EmbyAutomationAccountPreparationError.authenticatedIdentityMismatch
        }
        let item = try await client.item(withID: fixture.itemID, on: authenticated)
        guard item.metadata.id == fixture.itemID else {
            throw EmbyAutomationAccountPreparationError.fixtureItemMismatch
        }
        let playback = try await client.playbackInfo(for: item, on: authenticated)
        let matchingSources = playback.mediaSources.filter {
            $0.id == fixture.mediaSourceID
        }
        guard matchingSources.count == 1, let source = matchingSources.first else {
            throw EmbyAutomationAccountPreparationError.mediaSourceMismatch
        }
        let externalSubtitles = source.mediaStreams.filter {
            $0.kind == .subtitle && $0.isExternal
        }
        guard externalSubtitles.count == 1,
              let subtitle = externalSubtitles.first,
              subtitle.index == fixture.externalSubtitleStreamIndex,
              subtitle.codec?.isEmpty == false,
              subtitle.deliveryURL?.isEmpty == false else {
            throw EmbyAutomationAccountPreparationError.externalSubtitleMismatch
        }
        try await install(authenticated)
        return EmbyAutomationAccountPreparationReceipt(
            identityDigest: actualDigest,
            server: authenticated,
            fixture: fixture
        )
    }
#endif

    private func install(_ authenticated: EmbyAuthenticatedServer) async throws {
        try store.saveServer(authenticated)
        server = authenticated
        persistenceErrorMessage = nil
        await configurePlaybackBridge()
    }

    public func signOut() async {
        do {
            try store.deleteServer()
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
        server = nil
        playbackQueue = .empty
        playbackEvidence = nil
#if DEBUG
        evidenceJournal = EmbyEvidenceJournal()
#endif
        navigation.reset()
        await playbackBridge.configure(server: nil)
    }

    public func handleRequestError(_ error: Error) async -> Bool {
        guard case EmbyError.httpStatus(401) = error else { return false }
        await signOut()
        return true
    }

    public func playbackRequest(
        for selection: EmbyPlaybackSelection
    ) async throws -> PlaybackLaunchRequest {
        await configurePlaybackBridge()
        do {
            let request = try await playbackBridge.request(for: selection)
            playbackQueue = await playbackBridge.queueSnapshot
            return request
        } catch {
            _ = await handleRequestError(error)
            throw error
        }
    }

    public func nextPlaybackRequest() async -> PlaybackLaunchRequest? {
        let request = await playbackBridge.nextRequest()
        playbackQueue = await playbackBridge.queueSnapshot
        return request
    }

    public func playbackRequest(forQueueID id: UUID) async -> PlaybackLaunchRequest? {
        let request = await playbackBridge.request(for: id)
        playbackQueue = await playbackBridge.queueSnapshot
        return request
    }

    public func playbackQueueSnapshot() async -> PlaybackQueueSnapshot {
        let snapshot = await playbackBridge.queueSnapshot
        playbackQueue = snapshot
        return snapshot
    }

#if DEBUG
    public func recordReachability(_ action: String) {
        diagnosticProbe?("reachability emby delivered action=\(action)")
    }

    public func recordHomeActivation(
        surface: EmbyHomeCardSurface,
        cardIdentifier: String,
        item: EmbyLibraryItem,
        resultingItemID: EmbyItemID
    ) {
        evidenceJournal.recordHomeActivation(
            surface: surface,
            cardIdentifier: cardIdentifier,
            item: item,
            resultingItemID: resultingItemID
        )
    }

    public func recordDetail(item: EmbyLibraryItem, children: EmbyDetailChildren) {
        evidenceJournal.recordDetail(item: item, children: children)
    }

    public func recordSeasonTransition(
        seriesID: EmbyItemID,
        declaredSeasons: [EmbySeason],
        requestedSeasonID: EmbyItemID,
        beforeSelectedSeasonID: EmbyItemID?,
        beforeEpisodes: [EmbyEpisode],
        afterSelectedSeasonID: EmbyItemID?,
        afterEpisodes: [EmbyEpisode]
    ) {
        evidenceJournal.recordSeasonTransition(
            seriesID: seriesID,
            declaredSeasons: declaredSeasons,
            requestedSeasonID: requestedSeasonID,
            beforeSelectedSeasonID: beforeSelectedSeasonID,
            beforeEpisodes: beforeEpisodes,
            afterSelectedSeasonID: afterSelectedSeasonID,
            afterEpisodes: afterEpisodes
        )
    }

    public func warmArtwork(_ requests: [EmbyArtworkLoadRequest]) async {
        var seen = Set<URL>()
        let uniqueRequests = requests.prefix(60).filter { seen.insert($0.url).inserted }
        let loader = artworkEvidenceLoader
        let evidence = await withTaskGroup(
            of: (Int, EmbyArtworkEvidence).self,
            returning: [EmbyArtworkEvidence].self
        ) { group in
            var iterator = Array(uniqueRequests.enumerated()).makeIterator()
            for _ in 0..<min(4, uniqueRequests.count) {
                guard let (index, request) = iterator.next() else { break }
                group.addTask { (index, await loader.load(request)) }
            }
            var output: [(Int, EmbyArtworkEvidence)] = []
            while let result = await group.next() {
                output.append(result)
                if let (index, request) = iterator.next() {
                    group.addTask { (index, await loader.load(request)) }
                }
            }
            return output.sorted { $0.0 < $1.0 }.map(\.1)
        }
        for observation in evidence {
            evidenceJournal.recordArtwork(observation)
        }
    }
#endif

    private func configurePlaybackBridge() async {
        await playbackBridge.configure(server: server) { [weak self] in
            await self?.signOut()
        } onAcceptedReport: { [weak self] report in
            await self?.recordAcceptedPlaybackReport(report)
        } onPreparedPlayback: { [weak self] evidence in
#if DEBUG
            await self?.recordPreparedPlayback(evidence)
#endif
        }
    }

    private func recordAcceptedPlaybackReport(_ report: EmbyAcceptedPlaybackReport) {
        if var evidence = playbackEvidence,
           evidence.playSessionID == report.playSessionID {
            evidence.record(report)
            playbackEvidence = evidence
        } else {
            playbackEvidence = EmbyPlaybackEvidence(report: report)
        }
#if DEBUG
        evidenceJournal.recordAcceptedPlaybackReport(report)
#endif
    }

#if DEBUG
    private func recordPreparedPlayback(_ evidence: EmbyPreparedPlaybackEvidence) {
        evidenceJournal.recordPreparedPlayback(evidence)
    }
#endif
}

@MainActor
@Observable
public final class EmbyConnectionViewModel {
    public var address = ""
    public var username = ""
    public var password = ""
    public private(set) var isConnecting = false
    public private(set) var errorMessage: String?

    private let session: EmbySessionViewModel

    public init(session: EmbySessionViewModel) {
        self.session = session
        address = session.server?.baseAddress.absoluteString ?? ""
    }

    @discardableResult
    public func connect() async -> Bool {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressValue = value.contains("://") ? value : "http://" + value
        guard let url = URL(string: addressValue), url.host != nil else {
            errorMessage = "Enter a valid server address."
            return false
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await session.connect(
                address: url,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            errorMessage = nil
            password = ""
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
