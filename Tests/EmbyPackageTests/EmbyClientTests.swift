import Foundation
import MediaSource
import Testing
@testable import Emby

@Suite(.serialized)
struct EmbyClientTests {
    @Test("authentication uses the name endpoint and returns a complete server identity")
    func authentication() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            switch request.url?.path {
            case "/emby/System/Info/Public":
                return try response(
                    request,
                    status: 200,
                    json: "{\"Id\":\"server-live\",\"ServerName\":\"Live\",\"Version\":\"4.9.5.0\",\"LocalAddresses\":[],\"RemoteAddresses\":[]}"
                )
            case "/emby/Users/AuthenticateByName":
                return try response(
                    request,
                    status: 200,
                    json: "{\"User\":{\"Id\":\"user-live\"},\"AccessToken\":\"access-token\",\"ServerId\":\"server-live\"}"
                )
            default:
                return try response(request, status: 404, json: "missing")
            }
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        let authenticated = try await client.authenticate(
            address: URL(string: "http://example.test")!,
            username: "Cortisol",
            password: "secret"
        )

        #expect(authenticated.id.rawValue == "server-live")
        #expect(authenticated.name == "Live")
        #expect(authenticated.accessToken == "access-token")
        #expect(authenticated.userID.rawValue == "user-live")
        let request = try #require(recorder.requests.last)
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["Username": "Cortisol", "Pw": "secret"])
    }

    @Test("item queries send typed sorting and parse supported item variants")
    func itemQuery() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            return try response(
                request,
                status: 200,
                json: """
                {
                  "Items": [
                    {
                      "Id": "movie-1",
                      "Name": "Feature",
                      "Type": "Movie",
                      "Overview": "Overview",
                      "RunTimeTicks": 10000000,
                      "Etag": "item-etag",
                      "Size": 123,
                      "ImageTags": {"Primary": "primary-tag"},
                      "BackdropImageTags": ["backdrop-tag"],
                      "UserData": {
                        "PlaybackPositionTicks": 5000000,
                        "Played": false,
                        "UnplayedItemCount": 2
                      }
                    },
                    {"Id": "series-1", "Name": "Series", "Type": "Series"},
                    {
                      "Id": "season-1",
                      "Name": "Season 1",
                      "Type": "Season",
                      "SeriesId": "series-1",
                      "IndexNumber": 1
                    },
                    {
                      "Id": "episode-1",
                      "Name": "Episode 1",
                      "Type": "Episode",
                      "SeriesId": "series-1",
                      "SeasonId": "season-1",
                      "ParentIndexNumber": 1,
                      "IndexNumber": 1
                    },
                    {"Id": "boxset-1", "Name": "Collection", "Type": "BoxSet"},
                    {"Id": "folder-1", "Name": "Folder", "Type": "Folder"}
                  ],
                  "TotalRecordCount": 6
                }
                """
            )
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        let page = try await client.items(
            in: EmbyItemID(rawValue: "view-1"),
            on: server,
            query: EmbyItemQuery(
                sortBy: [.premiereDate, .sortName],
                sortOrder: .descending,
                startIndex: 10,
                limit: 20,
                includeItemTypes: [.movie, .boxSet],
                recursive: false
            )
        )

        #expect(page.items.count == 5)
        #expect(page.totalRecordCount == 6)
        #expect(page.items.first?.metadata.userData?.playbackPositionTicks == 5_000_000)
        #expect(page.items.first?.metadata.imageTags.primary?.rawValue == "primary-tag")
        let requestURL = try #require(recorder.requests.first?.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(components.path == "/emby/Users/user-1/Items")
        #expect(query["ParentId"] == "view-1")
        #expect(query["SortBy"] == "PremiereDate,SortName")
        #expect(query["SortOrder"] == "Descending")
        #expect(query["StartIndex"] == "10")
        #expect(query["Limit"] == "20")
        #expect(query["IncludeItemTypes"] == "Movie,BoxSet")
        #expect(query["Recursive"] == "false")
    }

    @Test("a single item refresh uses the authenticated user item route")
    func singleItem() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            return try response(
                request,
                status: 200,
                json: "{\"Id\":\"movie-1\",\"Name\":\"Fresh\",\"Type\":\"Movie\",\"UserData\":{\"PlaybackPositionTicks\":90000000}}"
            )
        }
        defer { MockURLProtocol.setHandler(nil) }

        let item = try await makeClient().item(
            withID: EmbyItemID(rawValue: "movie-1"),
            on: server
        )

        #expect(item.metadata.name == "Fresh")
        #expect(item.metadata.userData?.playbackPositionTicks == 90_000_000)
        #expect(recorder.requests.first?.url?.path == "/emby/Users/user-1/Items/movie-1")
    }

    @Test("children select the server entity type implied by the parent")
    func typedChildren() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            return try response(request, status: 200, json: "{\"Items\":[],\"TotalRecordCount\":0}")
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        let series = EmbyLibraryItem.series(EmbySeries(metadata: metadata(id: "series-1")))
        _ = try await client.children(of: series, on: server)

        let url = try #require(recorder.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "ParentId" }?.value == "series-1")
        #expect(query.first { $0.name == "IncludeItemTypes" }?.value == "Season")
    }

    @Test("views, resume, next up, and search use their Emby 4.9 routes")
    func discoveryRoutes() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            return try response(request, status: 200, json: "{\"Items\":[],\"TotalRecordCount\":0}")
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        _ = try await client.views(on: server)
        _ = try await client.resumeItems(on: server)
        _ = try await client.nextUp(on: server, seriesID: EmbyItemID(rawValue: "series-1"))
        _ = try await client.search("matrix", on: server)

        let paths = recorder.requests.compactMap(\.url?.path)
        #expect(paths == [
            "/emby/Users/user-1/Views",
            "/emby/Users/user-1/Items/Resume",
            "/emby/Shows/NextUp",
            "/emby/Users/user-1/Items",
        ])
        let nextUpQuery = URLComponents(
            url: try #require(recorder.requests[2].url),
            resolvingAgainstBaseURL: false
        )?.queryItems
        #expect(nextUpQuery?.first { $0.name == "UserId" }?.value == "user-1")
        #expect(nextUpQuery?.first { $0.name == "SeriesId" }?.value == "series-1")
        let searchQuery = URLComponents(
            url: try #require(recorder.requests[3].url),
            resolvingAgainstBaseURL: false
        )?.queryItems
        #expect(searchQuery?.first { $0.name == "SearchTerm" }?.value == "matrix")
    }

    @Test("playback info exposes original bytes and typed stream metadata")
    func directPlay() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            return try response(
                request,
                status: 200,
                json: """
                {
                  "PlaySessionId": "play-session",
                  "MediaSources": [
                    {
                      "Id": "source-1",
                      "Name": "Director's Cut",
                      "Container": "mkv",
                      "Size": 1234,
                      "SupportsDirectPlay": true,
                      "DefaultAudioStreamIndex": 1,
                      "DefaultSubtitleStreamIndex": 2,
                      "MediaStreams": [
                        {"Index":0,"Type":"Video","Codec":"hevc","IsDefault":true},
                        {"Index":1,"Type":"Audio","Codec":"aac","Language":"eng","DisplayTitle":"English","Channels":6,"IsDefault":true},
                        {"Index":2,"Type":"Subtitle","Codec":"srt","Language":"eng","DisplayTitle":"English SDH","IsForced":false,"IsExternal":true,"DeliveryUrl":"/subtitle"}
                      ]
                    },
                    {
                      "Id": "source-2",
                      "Container": "mp4",
                      "SupportsDirectPlay": false,
                      "MediaStreams": []
                    }
                  ]
                }
                """
            )
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        let item = EmbyLibraryItem.movie(EmbyMovie(metadata: metadata(
            id: "movie-1",
            entityTag: "etag-1",
            runTimeTicks: 90_000_000
        )))
        let playback = try await client.playbackInfo(for: item, on: server)

        #expect(playback.id.rawValue == "play-session")
        let source = try #require(playback.mediaSources.first)
        #expect(playback.mediaSources.count == 1)
        #expect(source.displayName == "Director's Cut")
        #expect(source.defaultStreamIndexes.video == 0)
        #expect(source.defaultStreamIndexes.audio == 1)
        #expect(source.defaultStreamIndexes.subtitle == 2)
        #expect(source.mediaStreams[1].language == "eng")
        #expect(source.mediaStreams[2].deliveryURL == "/subtitle")
        let directURL = try #require(URLComponents(url: source.directPlayURL, resolvingAgainstBaseURL: false))
        let directQuery = Dictionary(uniqueKeysWithValues: (directURL.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(directURL.path == "/emby/Videos/movie-1/stream.mkv")
        #expect(directQuery["Static"] == "true")
        #expect(directQuery["MediaSourceId"] == "source-1")
        #expect(directQuery["api_key"] == "token")
        #expect(source.versionedIdentity != nil)

        let subtitleURL = try client.externalSubtitleURL(
            for: source.mediaStreams[2],
            on: server
        )
        let subtitleComponents = try #require(URLComponents(
            url: subtitleURL,
            resolvingAgainstBaseURL: false
        ))
        #expect(subtitleComponents.path == "/emby/subtitle")
        #expect(subtitleComponents.queryItems?.first { $0.name == "api_key" }?.value == "token")

        let request = try #require(recorder.requests.first)
        #expect(request.url?.path == "/emby/Items/movie-1/PlaybackInfo")
        let requestBody = try #require(request.httpBody)
        let requestJSON = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        #expect(requestJSON["EnableDirectPlay"] as? Bool == true)
        #expect(requestJSON["EnableDirectStream"] as? Bool == false)
        #expect(requestJSON["EnableTranscoding"] as? Bool == false)
        #expect(requestJSON["IsPlayback"] as? Bool == true)
    }

    @Test("playback info rejects a source that requires server conversion")
    func transcodingIsRejected() async throws {
        MockURLProtocol.setHandler { request in
            try response(
                request,
                status: 200,
                json: """
                {
                  "PlaySessionId":"session",
                  "MediaSources":[
                    {"Id":"source","Container":"mp4","SupportsDirectPlay":false,"MediaStreams":[]}
                  ]
                }
                """
            )
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        let item = EmbyLibraryItem.movie(EmbyMovie(metadata: metadata(id: "movie-1")))

        await #expect(throws: EmbyError.directPlayUnavailable(EmbyItemID(rawValue: "movie-1"))) {
            try await client.playbackInfo(for: item, on: server)
        }
    }

    @Test("image URL size is typed and identity components do not collide")
    func typedURLsAndIdentity() throws {
        let client = makeClient()
        let size = try EmbyImageSize.fitting(maxWidth: 600, maxHeight: 900)
        let url = try client.imageURL(
            for: EmbyItemID(rawValue: "movie-1"),
            type: .primary,
            tag: EmbyImageTag(rawValue: "image-tag"),
            size: size,
            on: server
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["MaxWidth"] == "600")
        #expect(query["MaxHeight"] == "900")
        #expect(query["Tag"] == "image-tag")
        #expect(throws: EmbyError.invalidImageSize) { try EmbyImageSize.width(0) }

        let first = MediaIdentity.emby(serverID: "server", itemID: "item", mediaSourceID: "source")
        let otherServer = MediaIdentity.emby(serverID: "other", itemID: "item", mediaSourceID: "source")
        let otherItem = MediaIdentity.emby(serverID: "server", itemID: "other", mediaSourceID: "source")
        let otherSource = MediaIdentity.emby(serverID: "server", itemID: "item", mediaSourceID: "other")
        #expect(Set([first, otherServer, otherItem, otherSource]).count == 4)
        let firstRevision = ContentRevision.emby(itemEntityTag: "etag", sizeInBytes: 10)
        let replacedBytes = ContentRevision.emby(itemEntityTag: "etag", sizeInBytes: 11)
        let changedItem = ContentRevision.emby(itemEntityTag: "other", sizeInBytes: 10)
        #expect(Set([firstRevision, replacedBytes, changedItem]).count == 3)
    }

    @Test("reporting sends awaitable direct-play events")
    func reportingSendsEvents() async throws {
        let recorder = RequestRecorder()
        MockURLProtocol.setHandler { request in
            recorder.record(request)
            return try response(request, status: 204, json: "")
        }
        defer { MockURLProtocol.setHandler(nil) }
        let client = makeClient()
        let report = EmbyPlaybackReport(
            itemID: EmbyItemID(rawValue: "movie-1"),
            mediaSourceID: EmbyMediaSourceID(rawValue: "source-1"),
            playSessionID: EmbyPlaySessionID(rawValue: "session-1"),
            positionTicks: 42,
            audioStreamIndex: 1,
            subtitleStreamIndex: 2
        )
        try await client.sendPlayingStarted(report, on: server)
        try await client.sendProgress(report, on: server)
        try await client.sendStopped(report, on: server)

        let paths = recorder.requests.compactMap(\.url?.path)
        #expect(paths == [
            "/emby/Sessions/Playing",
            "/emby/Sessions/Playing/Progress",
            "/emby/Sessions/Playing/Stopped",
        ])
        for request in recorder.requests {
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["PositionTicks"] as? Int == 42)
            if request.url?.path != "/emby/Sessions/Playing/Stopped" {
                #expect(json["PlayMethod"] as? String == "DirectPlay")
            } else {
                #expect(json["PlayMethod"] == nil)
            }
        }
    }

    private var server: EmbyAuthenticatedServer {
        EmbyAuthenticatedServer(
            id: EmbyServerID(rawValue: "server-1"),
            name: "Server",
            baseAddress: URL(string: "http://example.test")!,
            accessToken: "token",
            userID: EmbyUserID(rawValue: "user-1")
        )
    }

    private func makeClient() -> EmbyClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return EmbyClient(
            session: URLSession(configuration: configuration),
            clientIdentity: EmbyClientIdentity(
                name: "Enchron",
                version: "1",
                deviceName: "Tests",
                deviceID: "tests"
            )
        )
    }

    private func metadata(
        id: String,
        entityTag: String? = nil,
        runTimeTicks: Int64? = nil
    ) -> EmbyItemMetadata {
        EmbyItemMetadata(
            id: EmbyItemID(rawValue: id),
            name: id,
            imageTags: EmbyImageTags(),
            overview: nil,
            runTimeTicks: runTimeTicks,
            userData: nil,
            entityTag: entityTag,
            sizeInBytes: nil
        )
    }
}

private func response(_ request: URLRequest, status: Int, json: String) throws -> (HTTPURLResponse, Data) {
    let url = try #require(request.url)
    let response = try #require(HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    ))
    return (response, Data(json.utf8))
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storage }
    }

    func record(_ request: URLRequest) {
        lock.withLock { storage.append(request) }
    }
}

private final class MockURLProtocolHandlerStore: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func set(_ handler: Handler?) {
        lock.withLock { self.handler = handler }
    }

    func get() -> Handler? {
        lock.withLock { handler }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = MockURLProtocolHandlerStore.Handler
    private static let handlerStore = MockURLProtocolHandlerStore()

    static func setHandler(_ handler: Handler?) {
        handlerStore.set(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handlerStore.get() else {
            client?.urlProtocol(self, didFailWithError: EmbyError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(Self.materialized(request))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func materialized(_ request: URLRequest) throws -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw stream.streamError ?? EmbyError.invalidResponse }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        var request = request
        request.httpBodyStream = nil
        request.httpBody = data
        return request
    }
}
