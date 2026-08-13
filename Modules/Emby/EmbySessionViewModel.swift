import Foundation
import Observation
import PlaybackFeature

@MainActor
@Observable
public final class EmbySessionViewModel {
    public let client: any EmbyClientProtocol
    public let playbackBridge: EmbyPlaybackBridge
    public private(set) var server: EmbyAuthenticatedServer?
    public private(set) var persistenceErrorMessage: String?

    private let store: any EmbyServerStoring

    public init(
        client: any EmbyClientProtocol,
        store: any EmbyServerStoring = KeychainEmbyServerStore()
    ) {
        self.client = client
        self.store = store
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
            return try await playbackBridge.request(for: selection)
        } catch {
            _ = await handleRequestError(error)
            throw error
        }
    }

    public func nextPlaybackRequest() async -> PlaybackLaunchRequest? {
        await playbackBridge.nextRequest()
    }

    public func playbackRequest(forQueueID id: UUID) async -> PlaybackLaunchRequest? {
        await playbackBridge.request(for: id)
    }

    public func playbackQueueSnapshot() async -> PlaybackQueueSnapshot {
        await playbackBridge.queueSnapshot
    }

    private func configurePlaybackBridge() async {
        await playbackBridge.configure(server: server) { [weak self] in
            await self?.signOut()
        }
    }
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
