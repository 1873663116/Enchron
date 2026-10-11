import Foundation
import Testing
@testable import MediaServer

private struct MediaServerLiveFixture: Decodable {
    let kind: MediaServerKind
    let address: URL
    let username: String
    let password: String
    let token: String
    let userID: String
    let itemID: String
}

@Suite(.serialized, .enabled(if: Bundle.module.url(forResource: "MediaServerLiveCredentials", withExtension: "local.json") != nil))
struct MediaServerLiveIntegrationTests {
    @Test("the same movie opens through every production service adapter")
    func sameMovieAcrossServices() async throws {
        let path = try #require(Bundle.module.url(forResource: "MediaServerLiveCredentials", withExtension: "local.json"))
        let fixtures = try JSONDecoder().decode([MediaServerLiveFixture].self, from: Data(contentsOf: path))
        #expect(fixtures.map(\.kind) == [.emby, .jellyfin, .plex])
        var prefixes: [Data] = []
        for fixture in fixtures {
            let identity = MediaServerClientIdentity(name: "Enchron Integration", version: "1", deviceName: "Simulator", deviceID: "enchron-service-tests")
            let client: any MediaServerClientProtocol
            let login: MediaServerLogin
            switch fixture.kind {
            case .emby, .jellyfin:
                client = MediaBrowserClient(dialect: fixture.kind == .emby ? .emby : .jellyfin, clientIdentity: identity)
                login = .password(address: fixture.address, username: fixture.username, password: fixture.password)
            case .plex:
                client = PlexClient(clientIdentity: identity)
                login = .plexToken(address: fixture.address, token: fixture.token, userID: fixture.userID)
            }
            let server = try await client.authenticate(login)
            #expect(server.kind == fixture.kind)
            let libraries = try await client.views(on: server)
            #expect(libraries.contains { $0.collectionType == "movies" })
            let item = try await client.item(withID: .init(rawValue: fixture.itemID), on: server)
            #expect(item.isPlayable)
            #expect(item.metadata.productionYear == 1982)
            let source = try #require(try await client.playbackInfo(for: item, on: server).mediaSources.first)
            #expect(source.mediaStreams.contains { $0.kind == .video && $0.codec == "hevc" })
            var request = URLRequest(url: source.directPlayURL)
            request.setValue("bytes=0-31", forHTTPHeaderField: "Range")
            let (bytes, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 206)
            #expect(bytes.count == 32)
            prefixes.append(bytes)
            let tag = try #require(item.metadata.imageTags.primary)
            let image = try client.imageURL(for: item.metadata.id, type: .primary, tag: tag, size: nil, on: server)
            let (_, imageResponse) = try await URLSession.shared.data(from: image)
            #expect((imageResponse as? HTTPURLResponse)?.statusCode == 200)
            let results = try await client.search("Blade Runner", on: server, query: .init(includeItemTypes: [.movie]))
            #expect(results.items.contains { $0.metadata.id == item.metadata.id })
        }
        #expect(prefixes.count == 3)
        #expect(prefixes[0] == prefixes[1])
        #expect(prefixes[1] == prefixes[2])
    }
}
