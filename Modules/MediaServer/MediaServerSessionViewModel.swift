import CryptoKit
import Foundation
import MediaSource
import Observation
import Playback

@MainActor
@Observable
public final class MediaServerSessionViewModel {
    public let client: any MediaServerClientProtocol
    public let playbackBridge: MediaServerPlaybackBridge
    public private(set) var server: MediaServerAuthenticatedServer?
    public private(set) var persistenceErrorMessage: String?
    public private(set) var playbackQueue: PlaybackQueueSnapshot = .empty
    public private(set) var resumeCatalogRevision: UInt64 = 0
#if DEBUG
    public private(set) var evidenceJournal = MediaServerEvidenceJournal()
#endif

    private let store: any MediaServerServerStoring
    private let navigation: MediaServerNavigationModel
#if DEBUG
    private let artworkEvidenceLoader = MediaServerArtworkEvidenceLoader(
        store: .shared,
        session: MediaSourceNetwork.shared.session
    )
#endif

#if DEBUG
    @ObservationIgnored public var diagnosticProbe: ((String) -> Void)?
#endif

    public init(
        client: any MediaServerClientProtocol,
        store: any MediaServerServerStoring = KeychainMediaServerStore(),
        navigation: MediaServerNavigationModel = MediaServerNavigationModel()
    ) {
        self.client = client
        self.store = store
        self.navigation = navigation
        let loadedServer: MediaServerAuthenticatedServer?
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
        playbackBridge = MediaServerPlaybackBridge(client: client, server: loadedServer)
    }

    public func connect(address: URL, username: String, password: String) async throws {
        let authenticated = try await client.authenticate(.password(address: address, username: username, password: password))
        try await install(authenticated)
    }

#if DEBUG
    public func embySignIn(
        identityData: Data,
        expectedIdentityDigest: String
    ) async throws -> MediaServerSignInReceipt {
        let actualDigest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == expectedIdentityDigest else {
            throw MediaServerSignInError.identityDigestMismatch
        }
        let rawDocument: Any
        do {
            rawDocument = try JSONSerialization.jsonObject(with: identityData)
        } catch {
            throw MediaServerSignInError.invalidIdentity
        }
        guard let rawIdentity = rawDocument as? [String: Any],
              Set(rawIdentity.keys) == MediaServerAutomationRuntimeIdentity.keys else {
            throw MediaServerSignInError.invalidIdentity
        }
        let identity: MediaServerAutomationRuntimeIdentity
        do {
            identity = try JSONDecoder().decode(
                MediaServerAutomationRuntimeIdentity.self,
                from: identityData
            )
        } catch {
            throw MediaServerSignInError.invalidIdentity
        }
        guard identity.schema == MediaServerAutomationRuntimeIdentity.schemaValue,
              identity.address.isEmpty == false,
              identity.username.isEmpty == false,
              identity.password.isEmpty == false,
              identity.serverID.isEmpty == false,
              identity.userID.isEmpty == false,
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
            throw MediaServerSignInError.invalidIdentity
        }
        let authenticated = try await client.authenticate(.password(address: address, username: identity.username, password: identity.password))
        guard authenticated.id.rawValue == identity.serverID,
              authenticated.userID.rawValue == identity.userID else {
            throw MediaServerSignInError.authenticatedIdentityMismatch
        }
        try await install(authenticated)
        return MediaServerSignInReceipt(
            identityDigest: actualDigest,
            server: authenticated
        )
    }
#endif

    public func install(_ authenticated: MediaServerAuthenticatedServer) async throws {
        guard authenticated.kind == client.kind else { throw MediaServerError.invalidResponse }
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
        resumeCatalogRevision = 0
#if DEBUG
        evidenceJournal = MediaServerEvidenceJournal()
#endif
        navigation.reset()
        await playbackBridge.configure(server: nil)
    }

    public func handleRequestError(_ error: Error) async -> Bool {
        guard case MediaServerError.httpStatus(401) = error else { return false }
        await signOut()
        return true
    }

    public func playbackRequest(
        for selection: MediaServerPlaybackSelection
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

    public var hasNextPlaybackRequest: Bool {
        guard let index = playbackQueue.entries.firstIndex(where: { $0.isCurrent })
        else { return false }
        return playbackQueue.entries.indices.contains(index + 1)
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
        surface: MediaServerHomeCardSurface,
        cardIdentifier: String,
        item: MediaServerLibraryItem,
        resultingItemID: MediaServerItemID
    ) {
        evidenceJournal.recordHomeActivation(
            surface: surface,
            cardIdentifier: cardIdentifier,
            item: item,
            resultingItemID: resultingItemID
        )
    }

    public func recordDetail(item: MediaServerLibraryItem, children: MediaServerDetailChildren) {
        evidenceJournal.recordDetail(item: item, children: children)
    }

    public func recordSeasonTransition(
        seriesID: MediaServerItemID,
        declaredSeasons: [MediaServerSeason],
        requestedSeasonID: MediaServerItemID,
        beforeSelectedSeasonID: MediaServerItemID?,
        beforeEpisodes: [MediaServerEpisode],
        afterSelectedSeasonID: MediaServerItemID?,
        afterEpisodes: [MediaServerEpisode]
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

    public func warmArtwork(_ requests: [MediaServerArtworkLoadRequest]) async {
        var seen = Set<URL>()
        let uniqueRequests = requests.prefix(60).filter { seen.insert($0.url).inserted }
        let loader = artworkEvidenceLoader
        let evidence = await withTaskGroup(
            of: (Int, MediaServerArtworkEvidence).self,
            returning: [MediaServerArtworkEvidence].self
        ) { group in
            var iterator = Array(uniqueRequests.enumerated()).makeIterator()
            for _ in 0..<min(4, uniqueRequests.count) {
                guard let (index, request) = iterator.next() else { break }
                group.addTask { (index, await loader.load(request)) }
            }
            var output: [(Int, MediaServerArtworkEvidence)] = []
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
            await self?.acceptPlaybackReport(report)
        } onPreparedPlayback: { [weak self] evidence in
#if DEBUG
            await self?.recordPreparedPlayback(evidence)
#endif
        }
    }

    private func acceptPlaybackReport(_ report: MediaServerAcceptedPlaybackReport) {
#if DEBUG
        recordAcceptedPlaybackReport(report)
#endif
        guard report.event == .stopped,
              report.serverID == server?.id,
              report.userID == server?.userID else { return }
        resumeCatalogRevision &+= 1
    }

#if DEBUG
    private func recordAcceptedPlaybackReport(_ report: MediaServerAcceptedPlaybackReport) {
        evidenceJournal.recordAcceptedPlaybackReport(report)
    }

    private func recordPreparedPlayback(_ evidence: MediaServerPreparedPlaybackEvidence) {
        evidenceJournal.recordPreparedPlayback(evidence)
    }
#endif
}

@MainActor
@Observable
public final class MediaServerConnectionViewModel {
    public var address = ""
    public var username = ""
    public var password = ""
    public private(set) var isConnecting = false
    public private(set) var errorMessage: String?

    private let session: MediaServerSessionViewModel
    private let cleartextExposurePolicy: CleartextExposurePolicy

    public init(
        session: MediaServerSessionViewModel,
        cleartextExposurePolicy: CleartextExposurePolicy = .shared
    ) {
        self.session = session
        self.cleartextExposurePolicy = cleartextExposurePolicy
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
        guard await cleartextExposurePolicy.authorize(url) else {
            errorMessage = nil
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
