import DesignSystem
import Foundation
import MediaSource
import Observation
import SwiftUI

struct PlexPIN: Decodable, Sendable {
    let id: Int
    let code: String
    let authToken: String?
    let expiresIn: Int?
}

struct PlexResource: Decodable, Identifiable, Sendable {
    let name: String
    let clientIdentifier: String
    let provides: String
    let accessToken: String?
    let connections: [Connection]
    var id: String { clientIdentifier }

    struct Connection: Decodable, Sendable {
        let uri: URL
        let local: Bool
        let relay: Bool?
    }
}

private struct PlexUser: Decodable, Sendable { let id: Int }

@MainActor
@Observable
final class PlexAccount {
    enum State {
        case idle
        case authorizing(URL)
        case servers([PlexResource], userID: String)
        case connecting
    }

    private(set) var state: State = .idle
    private(set) var error: String?
    private let client: PlexClient
    private let session: MediaServerSessionViewModel
    private var task: Task<Void, Never>?

    init(client: PlexClient, session: MediaServerSessionViewModel) {
        self.client = client
        self.session = session
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    func start(open: @escaping (URL) -> Void) {
        cancel()
        error = nil
        task = Task {
            do {
                let pin: PlexPIN = try await request(path: "/api/v2/pins", method: "POST",
                                                     parameters: [.init(name: "strong", value: "true")])
                var query = URLComponents()
                query.queryItems = [.init(name: "clientID", value: client.clientIdentity.deviceID),
                                    .init(name: "code", value: pin.code),
                                    .init(name: "context[device][product]", value: client.clientIdentity.name)]
                guard let url = URL(string: "https://app.plex.tv/auth#?" + (query.percentEncodedQuery ?? "")) else {
                    throw MediaServerError.invalidResponse
                }
                try Task.checkCancellation()
                state = .authorizing(url)
                open(url)
                let deadline = Date().addingTimeInterval(TimeInterval(pin.expiresIn ?? 300))
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(1))
                    let result: PlexPIN = try await request(path: "/api/v2/pins/\(pin.id)",
                                                           parameters: [.init(name: "code", value: pin.code)])
                    if let token = result.authToken, !token.isEmpty {
                        async let user: PlexUser = request(path: "/api/v2/user", token: token)
                        async let resources: [PlexResource] = request(path: "/api/v2/resources", token: token,
                                                                      parameters: [.init(name: "includeHttps", value: "1")])
                        let servers = try await resources.filter { $0.provides.split(separator: ",").contains("server") && $0.accessToken != nil }
                        let userID = try await String(user.id)
                        try Task.checkCancellation()
                        state = .servers(servers, userID: userID)
                        return
                    }
                }
                error = "Plex sign-in expired. Please try again."
                state = .idle
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
                state = .idle
            }
        }
    }

    func connect(_ resource: PlexResource, userID: String) {
        task?.cancel()
        task = Task { await connectToServer(resource, userID: userID) }
    }

    private func connectToServer(_ resource: PlexResource, userID: String) async {
        guard let token = resource.accessToken else { return }
        state = .connecting
        error = nil
        var lastError: (any Error)?
        let connections = resource.connections.sorted { left, right in
            func rank(_ value: PlexResource.Connection) -> Int {
                (value.uri.scheme == "https" ? 4 : 0) + (value.local ? 2 : 0) + (value.relay == true ? 0 : 1)
            }
            return rank(left) > rank(right)
        }
        for connection in connections {
            do {
                guard await CleartextExposurePolicy.shared.authorize(connection.uri) else { continue }
                let authenticated = try await client.authenticate(.plexToken(address: connection.uri, token: token, userID: userID))
                guard authenticated.id.rawValue == resource.clientIdentifier else { throw MediaServerError.invalidResponse }
                try Task.checkCancellation()
                try await session.install(authenticated)
                state = .idle
                return
            } catch is CancellationError {
                return
            } catch {
                lastError = error
            }
        }
        error = lastError?.localizedDescription ?? "No available connection to this Plex server."
        state = .servers([resource], userID: userID)
    }

    private func request<Value: Decodable & Sendable>(path: String, method: String = "GET", token: String? = nil,
                                                     parameters: [URLQueryItem] = []) async throws -> Value {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "plex.tv"
        components.path = path
        components.queryItems = parameters
        guard let url = components.url else { throw MediaServerError.invalidBaseAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(client.clientIdentity.name, forHTTPHeaderField: "X-Plex-Product")
        request.setValue(client.clientIdentity.deviceID, forHTTPHeaderField: "X-Plex-Client-Identifier")
        if let token { request.setValue(token, forHTTPHeaderField: "X-Plex-Token") }
        let (data, response) = try await MediaSourceNetwork.shared.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw MediaServerError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else { throw MediaServerError.httpStatus(response.statusCode) }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}

struct PlexConnectionScreen: View {
    @State private var account: PlexAccount
    @Environment(\.openURL) private var openURL

    init(client: PlexClient, session: MediaServerSessionViewModel) {
        _account = State(initialValue: PlexAccount(client: client, session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            Text("Connect to Plex").font(.title)
            switch account.state {
            case .idle:
                Button("Sign in with Plex") { account.start { openURL($0) } }
                    .accessibilityIdentifier("Plex-Connection-SignIn")
            case .authorizing(let url):
                ProgressView("Waiting for Plex sign-in…")
                Link("Open Plex sign-in", destination: url)
                Button("Cancel") { account.cancel() }
            case .servers(let servers, let userID):
                Text(servers.isEmpty ? "No Plex media servers are available for this account." : "Choose a server")
                ForEach(servers) { server in
                    Button(server.name) { account.connect(server, userID: userID) }
                        .accessibilityIdentifier("Plex-Connection-Server-\(server.id)")
                }
                Button("Use another account") { account.start { openURL($0) } }
            case .connecting:
                ProgressView("Connecting…")
            }
            if let error = account.error {
                Text(error).foregroundStyle(.red).accessibilityIdentifier("Plex-Connection-Error")
            }
        }
        .frame(maxWidth: DesignTokens.SourceConnection.panelWidth)
        .padding(DesignTokens.Spacing.xxl)
        .onDisappear { account.cancel() }
    }
}
