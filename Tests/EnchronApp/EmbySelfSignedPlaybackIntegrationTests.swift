import Foundation
import MediaSource
@testable import Emby
import XCTest

nonisolated final class EmbySelfSignedPlaybackIntegrationTests: XCTestCase {
    func testApprovedSelfSignedCertificateAlsoCarriesTheMediaBytes() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawAddress = environment["ENCHRON_EMBY_TLS_TEST_URL"],
              let username = environment["ENCHRON_EMBY_TEST_USERNAME"],
              let password = environment["ENCHRON_EMBY_TEST_PASSWORD"] else {
            throw XCTSkip("Set ENCHRON_EMBY_TLS_TEST_URL and the ENCHRON_EMBY_TEST_* credentials to run the self-signed playback test.")
        }
        let address = try XCTUnwrap(URL(string: rawAddress))
        XCTAssertEqual(
            address.scheme,
            "https",
            "ENCHRON_EMBY_TLS_TEST_URL must be an https address for the certificate path to run."
        )

        ServerTrustPolicy.shared.approvalHandler = { _ in true }
        defer { ServerTrustPolicy.shared.approvalHandler = nil }

        let client = EmbyClient(clientIdentity: EmbyClientIdentity(
            name: "Enchron",
            version: "1",
            deviceName: "Self Signed Playback Tests",
            deviceID: "enchron-self-signed-playback-tests"
        ))
        let server = try await client.authenticate(
            address: address,
            username: username,
            password: password
        )
        let views = try await client.views(on: server)
        var playable: EmbyPlaybackSession?
        for view in views where playable == nil {
            let page = try await client.items(in: view.id, on: server, query: EmbyItemQuery(limit: 50))
            for item in page.items {
                switch item {
                case .movie, .episode:
                    playable = try? await client.playbackInfo(for: item, on: server)
                case .series, .season, .boxSet:
                    continue
                }
                if playable != nil { break }
            }
        }
        let session = try XCTUnwrap(playable, "The server exposed no directly playable title.")
        let source = try XCTUnwrap(session.mediaSources.first)
        let byteSource = EmbyMediaByteSource(
            streamURL: source.directPlayURL,
            accessToken: server.accessToken,
            contentLength: source.sizeInBytes
        )

        let read = try await byteSource.read(in: 0..<1_024)

        XCTAssertEqual(read.data.count, 1_024)
    }
}
