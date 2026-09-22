import CryptoKit
import Foundation
import MediaSource
import Observation
import Playback

@MainActor
@Observable
public final class EmbySessionViewModel {
    public let client: any EmbyClientProtocol
    public let playbackBridge: EmbyPlaybackBridge
    public private(set) var server: EmbyAuthenticatedServer?
    public private(set) var persistenceErrorMessage: String?
    public private(set) var playbackQueue: PlaybackQueueSnapshot = .empty
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
    public func embySignIn(
        identityData: Data,
        expectedIdentityDigest: String
    ) async throws -> EmbySignInReceipt {
        let actualDigest = "sha256:" + SHA256.hash(data: identityData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == expectedIdentityDigest else {
            throw EmbySignInError.identityDigestMismatch
        }
        let rawDocument: Any
        do {
            rawDocument = try JSONSerialization.jsonObject(with: identityData)
        } catch {
            throw EmbySignInError.invalidIdentity
        }
        guard let rawIdentity = rawDocument as? [String: Any],
              Set(rawIdentity.keys) == EmbyAutomationRuntimeIdentity.keys else {
            throw EmbySignInError.invalidIdentity
        }
        let identity: EmbyAutomationRuntimeIdentity
        do {
            identity = try JSONDecoder().decode(
                EmbyAutomationRuntimeIdentity.self,
                from: identityData
            )
        } catch {
            throw EmbySignInError.invalidIdentity
        }
        guard identity.schema == EmbyAutomationRuntimeIdentity.schemaValue,
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
            throw EmbySignInError.invalidIdentity
        }
        let authenticated = try await client.authenticate(
            address: address,
            username: identity.username,
            password: identity.password
        )
        guard authenticated.id.rawValue == identity.serverID,
              authenticated.userID.rawValue == identity.userID else {
            throw EmbySignInError.authenticatedIdentityMismatch
        }
        try await install(authenticated)
        return EmbySignInReceipt(
            identityDigest: actualDigest,
            server: authenticated
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
#if DEBUG
            await self?.recordAcceptedPlaybackReport(report)
#endif
        } onPreparedPlayback: { [weak self] evidence in
#if DEBUG
            await self?.recordPreparedPlayback(evidence)
#endif
        }
    }

#if DEBUG
    private func recordAcceptedPlaybackReport(_ report: EmbyAcceptedPlaybackReport) {
        evidenceJournal.recordAcceptedPlaybackReport(report)
    }

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
    private let cleartextExposurePolicy: CleartextExposurePolicy

    public init(
        session: EmbySessionViewModel,
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
