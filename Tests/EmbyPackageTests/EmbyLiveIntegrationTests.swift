import Foundation
import Testing
@testable import Emby

@Suite(.serialized)
struct EmbyLiveIntegrationTests {
    @Test("Emby 4.9 public system info is reachable without authentication")
    func publicSystemInfo() async throws {
        let credentials = try loadCredentials()
        let client = makeLiveClient()
        let info = try await client.publicSystemInfo(at: credentials.address)

        #expect(info.version == "4.9.5.0")
        #expect(info.id.rawValue.isEmpty == false)
    }

    @Test("authenticated Emby endpoints and original-byte streaming work")
    func authenticatedEndpoints() async throws {
        let credentials = try loadCredentials()
        guard credentials.password.isEmpty == false else {
            Issue.record("Fill the password in Tests/EmbyServerCredentials.local.json to run authenticated Emby integration tests.")
            return
        }
        let client = makeLiveClient()
        let server = try await client.authenticate(
            address: credentials.address,
            username: credentials.username,
            password: credentials.password
        )
        let views = try await client.views(on: server)
        var libraryItems: [EmbyLibraryItem] = []
        for view in views {
            let page = try await client.items(
                in: view.id,
                on: server,
                query: EmbyItemQuery(limit: 50)
            )
            libraryItems.append(contentsOf: page.items)
        }
        _ = try await client.resumeItems(on: server, query: EmbyItemQuery(limit: 20))
        _ = try await client.nextUp(on: server, limit: 20)
        if let first = libraryItems.first {
            _ = try await client.search(
                first.metadata.name,
                on: server,
                query: EmbyItemQuery(limit: 20)
            )
        }
        let playableItems = libraryItems.filter { item in
            switch item {
            case .movie, .episode: true
            case .series, .season, .boxSet: false
            }
        }
        var playableSession: EmbyPlaybackSession?
        for item in playableItems {
            do {
                playableSession = try await client.playbackInfo(for: item, on: server)
                break
            } catch EmbyError.directPlayUnavailable {
                continue
            }
        }
        let playback = try #require(playableSession)
        let source = try #require(playback.mediaSources.first)
        var request = URLRequest(url: source.directPlayURL)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(data.count == 1)
    }

    private func loadCredentials() throws -> EmbyServerCredentials {
        let url = try #require(Bundle.module.url(
            forResource: "EmbyServerCredentials",
            withExtension: "local.json"
        ))
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw EmbyLiveTestError.credentials("Read Tests/EmbyServerCredentials.local.json before running Emby integration tests.")
        }
        do {
            return try JSONDecoder().decode(EmbyServerCredentials.self, from: data)
        } catch {
            throw EmbyLiveTestError.credentials("Decode Tests/EmbyServerCredentials.local.json before running Emby integration tests.")
        }
    }

    private func makeLiveClient() -> EmbyClient {
        EmbyClient(
            clientIdentity: EmbyClientIdentity(
                name: "Enchron",
                version: "1",
                deviceName: "SwiftPM Tests",
                deviceID: "enchron-swiftpm-tests"
            )
        )
    }
}

private struct EmbyServerCredentials: Decodable {
    let address: URL
    let username: String
    let password: String
}

private enum EmbyLiveTestError: Error {
    case credentials(String)
}
