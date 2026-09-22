import Foundation
import Testing
import Playback
@testable import Emby

private func embyCredentialsAreInstalled() -> Bool {
    Bundle.module.url(
        forResource: "EmbyServerCredentials",
        withExtension: "local.json"
    ) != nil
}

@Suite(.serialized, .enabled(if: embyCredentialsAreInstalled()))
struct EmbyLiveIntegrationTests {
    @Test("a server-resumable item remains visible through the production client",
          .enabled(if: ProcessInfo.processInfo.environment["ENCHRON_EMBY_RESUME_ITEM_ID"] != nil))
    func expectedResumableItemIsVisible() async throws {
        let credentials = try loadCredentials()
        let client = makeLiveClient()
        let server = try await client.authenticate(
            address: credentials.address, username: credentials.username, password: credentials.password
        )
        let expectedID = try #require(ProcessInfo.processInfo.environment["ENCHRON_EMBY_RESUME_ITEM_ID"])
        let page = try await client.resumeItems(on: server)
        let item = try #require(page.items.first { $0.metadata.id.rawValue == expectedID })
        #expect((item.metadata.userData?.playbackPositionTicks ?? 0) > 0)
    }

    @Test("production playback reports persist track selections and reopening reads them back",
          .enabled(if: ProcessInfo.processInfo.environment["ENCHRON_EMBY_TRACK_FIXTURE_ID"] != nil))
    func trackSelectionsRoundTripThroughServer() async throws {
        let credentials = try loadCredentials()
        let client = makeLiveClient()
        let server = try await client.authenticate(
            address: credentials.address, username: credentials.username, password: credentials.password
        )
        let fixtureID = try #require(ProcessInfo.processInfo.environment["ENCHRON_EMBY_TRACK_FIXTURE_ID"])
        let item = try await client.item(withID: EmbyItemID(rawValue: fixtureID), on: server)
        try #require(item.metadata.name == "Enchron Regression Episode")
        let playback = try await client.playbackInfo(for: item, on: server)
        let source = try #require(playback.mediaSources.first)
        let audio = try #require(source.mediaStreams.first { $0.kind == .audio && $0.index != source.defaultStreamIndexes.audio })
        let subtitle = try #require(source.mediaStreams.first { $0.kind == .subtitle && !$0.isExternal })
        var originalRequest = URLRequest(url: server.baseAddress.appending(path: "Users/\(server.userID.rawValue)/Items/\(fixtureID)"))
        originalRequest.setValue(server.accessToken, forHTTPHeaderField: "X-Emby-Token")
        let (originalData, _) = try await URLSession.shared.data(for: originalRequest)
        let originalItem = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        let originalUserData = try #require(originalItem["UserData"] as? [String: Any])
        let bridge = EmbyPlaybackBridge(client: client, server: server)
        let selection = EmbyPlaybackSelection(item: item, mediaSourceID: source.id, startAction: .fromBeginning)

        func select(audioID: Int?, subtitleID: Int?) async throws -> PlaybackLaunchRequest {
            let request = try await bridge.request(for: selection)
            let reporter = try #require(request.sessionReporter as? EmbyPlaybackSessionReporter)
            let report = PlaybackSessionReport(
                positionSeconds: 0, isPaused: true,
                selectedAudioTrackID: audioID.map(String.init),
                selectedSubtitleTrackID: subtitleID.flatMap { $0 >= 0 ? "ffmpeg.subtitle.\($0)" : nil }
            )
            reporter.playbackStarted(report)
            reporter.playbackProgressed(report, reason: .audioTrackChange)
            reporter.playbackProgressed(report, reason: .subtitleTrackChange)
            reporter.playbackStopped(report)
            await reporter.waitForPendingReports()
            return try await bridge.request(for: selection)
        }

        func restore() async throws {
            _ = try await select(audioID: source.defaultStreamIndexes.audio, subtitleID: source.defaultStreamIndexes.subtitle)
            var request = originalRequest
            request.url = originalRequest.url?.appending(path: "UserData")
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: originalUserData)
            let (_, response) = try await URLSession.shared.data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 204)
        }

        do {
            let reopened = try await select(audioID: audio.index, subtitleID: subtitle.index)
            #expect(reopened.initialTrackSelection == TrackSelectionPreference(
                audioTrackID: String(audio.index), subtitleTrack: .track(id: "ffmpeg.subtitle.\(subtitle.index)")
            ))
            let disabled = try await select(audioID: audio.index, subtitleID: nil)
            #expect(disabled.initialTrackSelection?.audioTrackID == String(audio.index))
            #expect(disabled.initialTrackSelection?.subtitleTrack == .off)
        } catch {
            try await restore()
            throw error
        }
        try await restore()
    }

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
            Issue.record("Fill the password in Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json to run authenticated Emby integration tests.")
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
            throw EmbyLiveTestError.credentials("Read Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json before running Emby integration tests.")
        }
        do {
            return try JSONDecoder().decode(EmbyServerCredentials.self, from: data)
        } catch {
            throw EmbyLiveTestError.credentials("Decode Tests/EmbyPackageTests/Fixtures/EmbyServerCredentials.local.json before running Emby integration tests.")
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
