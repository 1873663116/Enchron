#if DEBUG
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import MediaSource

public struct EmbySignInReceipt: Codable, Equatable, Sendable {
    public static let schemaValue = "enchron.regression.emby-sign-in@1"
    public let schema: String
    public let identityDigest: String
    public let serverID: String
    public let userID: String
    public let persisted: Bool
    init(identityDigest: String, server: EmbyAuthenticatedServer) {
        schema = Self.schemaValue
        self.identityDigest = identityDigest
        serverID = server.id.rawValue
        userID = server.userID.rawValue
        persisted = true
    }
}
public enum EmbySignInError: Error, LocalizedError, Sendable {
    case identityDigestMismatch
    case invalidIdentity
    case authenticatedIdentityMismatch
    public var errorDescription: String? {
        switch self {
        case .identityDigestMismatch:
            "The Emby runtime identity digest did not match."
        case .invalidIdentity:
            "The Emby runtime identity document is invalid."
        case .authenticatedIdentityMismatch:
            "The authenticated Emby identity did not match the fixture authority."
        }
    }
}

struct EmbyAutomationRuntimeIdentity: Decodable {
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
    public let alternateTagCacheKey: String?
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
                alternateTagCacheKey: Self.alternateTagCacheKey(for: request),
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
                alternateTagCacheKey: Self.alternateTagCacheKey(for: request),
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
                alternateTagCacheKey: Self.alternateTagCacheKey(for: request),
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
            alternateTagCacheKey: Self.alternateTagCacheKey(for: request),
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

    private static func alternateTagCacheKey(
        for request: EmbyArtworkLoadRequest
    ) -> String? {
        guard var components = URLComponents(
            url: request.url,
            resolvingAgainstBaseURL: false
        ),
        let queryItems = components.queryItems,
        queryItems.contains(where: { $0.name == "Tag" }) else {
            return nil
        }
        components.queryItems = queryItems.map { item in
            item.name == "Tag"
                ? URLQueryItem(name: "Tag", value: "\(item.value ?? "")-alternate")
                : item
        }
        guard let alternate = components.url else { return nil }
        return ArtworkKey(remoteImageURL: alternate).debugStorageKey
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
        let playbackActionIDs: [String] = item.isPlayable ? ["Emby-Detail-Play"] : []
        detail = EmbyDetailEvidence(
            itemID: item.metadata.id.rawValue,
            itemKind: Self.kind(of: item),
            seriesID: seriesID?.rawValue,
            declaredSeasonIDs: seasons.map { $0.metadata.id.rawValue },
            selectedSeasonID: selectedSeasonID?.rawValue,
            episodeIDs: episodes.map { $0.metadata.id.rawValue },
            playbackActionIDs: playbackActionIDs
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
public struct EmbyPlaybackEvidence: Equatable, Sendable {
    private static let retainedReportLimit = 64

    public let serverID: EmbyServerID
    public let userID: EmbyUserID
    public let itemID: EmbyItemID
    public let mediaSourceID: EmbyMediaSourceID
    public let playSessionID: EmbyPlaySessionID
    public private(set) var activePositionTicks: Int64?
    public private(set) var latestPositionTicks: Int64
    public private(set) var exitPositionTicks: Int64?
    public private(set) var acceptedProgressReportCount: Int
    public private(set) var acceptedReports: [EmbyAcceptedPlaybackReport]
    public private(set) var totalAcceptedReportCount: Int

    public var acceptedReportsWereTruncated: Bool {
        totalAcceptedReportCount > acceptedReports.count
    }

    public init(report: EmbyAcceptedPlaybackReport) {
        serverID = report.serverID
        userID = report.userID
        itemID = report.itemID
        mediaSourceID = report.mediaSourceID
        playSessionID = report.playSessionID
        activePositionTicks = report.event == .started ? report.positionTicks : nil
        latestPositionTicks = report.positionTicks
        exitPositionTicks = report.event == .stopped ? report.positionTicks : nil
        acceptedProgressReportCount = report.event == .progress ? 1 : 0
        acceptedReports = [report]
        totalAcceptedReportCount = 1
    }

    public mutating func record(_ report: EmbyAcceptedPlaybackReport) {
        guard report.serverID == serverID,
              report.userID == userID,
              report.itemID == itemID,
              report.mediaSourceID == mediaSourceID,
              report.playSessionID == playSessionID else {
            return
        }
        if report.event == .started {
            activePositionTicks = report.positionTicks
        }
        if report.event == .progress {
            acceptedProgressReportCount += 1
        }
        if report.event == .stopped {
            exitPositionTicks = report.positionTicks
        }
        latestPositionTicks = report.positionTicks
        totalAcceptedReportCount += 1
        acceptedReports.append(report)
        if acceptedReports.count > Self.retainedReportLimit {
            acceptedReports.removeFirst(acceptedReports.count - Self.retainedReportLimit)
        }
    }
}
#endif
