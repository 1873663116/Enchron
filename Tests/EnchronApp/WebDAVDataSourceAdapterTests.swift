import Foundation
@testable import MediaLibrary
import Testing
@testable import Enchron

@Suite(.serialized)
struct WebDAVDataSourceAdapterTests {
    @Test("WebDAV sends authenticated depth-one PROPFIND and parses files and folders")
    func authenticatedPROPFIND() async throws {
        let recorder = WebDAVRequestRecorder()
        WebDAVTestURLProtocol.setHandler { request in
            recorder.record(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 207,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/xml"]
                  ) else {
                throw URLError(.badURL)
            }
            return (response, Data(Self.directoryListing.utf8))
        }
        defer { WebDAVTestURLProtocol.setHandler(nil) }

        let credentials = RecordingWebDAVCredentialStore(
            credential: .init(username: "viewer", password: "secret")
        )
        let adapter = WebDAVDataSourceAdapter(
            credentialStore: credentials,
            session: Self.makeSession()
        )
        let ownerID = UUID()
        adapter.ownerDataSourceID = ownerID
        let info = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "https://media.example.test/dav/library",
            username: "fallback"
        )

        try await adapter.connect(with: info)
        let files = try await adapter.listContents(at: "/")
        let folders = try await adapter.listFolders(at: "/")

        let movie = try #require(files.first)
        #expect(files.map(\.name) == ["Movie One.mkv"])
        #expect(movie.sizeInBytes == 12_345)
        #expect(movie.remoteEntityTag == "\"movie-one-v3\"")
        #expect(folders.map(\.name) == ["Season 1"])
        #expect(folders.first?.dataSourceID == ownerID)

        let requests = recorder.requests
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.httpMethod == "PROPFIND" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Depth") == "1" })
        let token = Data("viewer:secret".utf8).base64EncodedString()
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Basic \(token)" })
        #expect(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Content-Type") == "application/xml; charset=utf-8"
        })

        let playableSource = try await adapter.resolvePlayableSource(for: movie)
        defer { playableSource.accessLease?.release() }
        #expect(playableSource.url.scheme == "http")
        #expect(playableSource.url.host == "127.0.0.1")
        #expect(playableSource.url.user == nil)
        #expect(playableSource.url.password == nil)
        #expect(!playableSource.url.absoluteString.contains("viewer"))
        #expect(!playableSource.url.absoluteString.contains("secret"))
        #expect(!playableSource.url.absoluteString.contains("media.example.test"))
        #expect(credentials.loadedSourceIDs == [info.credentialSourceID])
    }

    @Test("WebDAV preserves a byte-range request on its resolved HTTP media URL")
    func rangeRequestOnResolvedURL() async throws {
        let recorder = WebDAVRequestRecorder()
        WebDAVTestURLProtocol.setHandler { request in
            recorder.record(request)
            let isPROPFIND = request.httpMethod == "PROPFIND"
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: isPROPFIND ? 207 : 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: isPROPFIND
                    ? ["Content-Type": "application/xml"]
                    : [
                        "Accept-Ranges": "bytes",
                        "Content-Range": "bytes 3-6/10",
                        "Content-Length": "4"
                    ]
                  ) else {
                throw URLError(.badURL)
            }
            return (response, isPROPFIND ? Data(Self.directoryListing.utf8) : Data("3456".utf8))
        }
        defer { WebDAVTestURLProtocol.setHandler(nil) }

        let credentials = RecordingWebDAVCredentialStore(
            credential: .init(username: "viewer", password: "secret")
        )
        let session = Self.makeSession()
        let adapter = WebDAVDataSourceAdapter(credentialStore: credentials, session: session)
        let info = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "https://media.example.test/library",
            username: "fallback"
        )
        try await adapter.connect(with: info)
        let fileURL = try #require(URL(string: "https://media.example.test/library/Feature.mp4"))
        let file = FileBrowsingDomain.MediaFile(
            name: "Feature.mp4",
            sizeInBytes: 10,
            modifiedAt: .distantPast,
            fileExtension: "mp4",
            url: fileURL
        )
        let playableSource = try await adapter.resolvePlayableSource(for: file)
        defer { playableSource.accessLease?.release() }

        var request = URLRequest(url: playableSource.url)
        request.setValue("bytes=3-6", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(httpResponse.value(forHTTPHeaderField: "Content-Range") == "bytes 3-6/10")
        #expect(data == Data("3456".utf8))
        #expect(recorder.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=3-6")
        let token = Data("viewer:secret".utf8).base64EncodedString()
        #expect(recorder.requests.last?.value(forHTTPHeaderField: "Authorization") == "Basic \(token)")
        #expect(playableSource.url.user == nil)
        #expect(playableSource.url.password == nil)
    }

    @Test("WebDAV playback lease survives browsing adapter disconnect")
    func playbackLeaseSurvivesAdapterDisconnect() async throws {
        let recorder = WebDAVRequestRecorder()
        WebDAVTestURLProtocol.setHandler { request in
            recorder.record(request)
            let isPROPFIND = request.httpMethod == "PROPFIND"
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: isPROPFIND ? 207 : 206,
                    httpVersion: "HTTP/1.1",
                    headerFields: isPROPFIND
                    ? ["Content-Type": "application/xml"]
                    : [
                        "Accept-Ranges": "bytes",
                        "Content-Range": "bytes 2-5/10",
                        "Content-Length": "4"
                    ]
                  ) else {
                throw URLError(.badURL)
            }
            return (response, isPROPFIND ? Data(Self.directoryListing.utf8) : Data("2345".utf8))
        }
        defer { WebDAVTestURLProtocol.setHandler(nil) }

        let credentials = RecordingWebDAVCredentialStore(
            credential: .init(username: "viewer", password: "secret")
        )
        let adapter = WebDAVDataSourceAdapter(
            credentialStore: credentials,
            session: Self.makeSession()
        )
        let info = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "https://media.example.test/library",
            username: "fallback"
        )
        try await adapter.connect(with: info)
        let fileURL = try #require(URL(string: "https://media.example.test/library/Feature.mp4"))
        let source = try await adapter.resolvePlayableSource(
            for: .init(
                name: "Feature.mp4",
                sizeInBytes: 10,
                modifiedAt: .distantPast,
                fileExtension: "mp4",
                url: fileURL
            )
        )
        defer { source.accessLease?.release() }

        adapter.disconnect()

        var request = URLRequest(url: source.url)
        request.setValue("bytes=2-5", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        #expect(httpResponse.statusCode == 206)
        #expect(data == Data("2345".utf8))
        #expect(recorder.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=2-5")
        let token = Data("viewer:secret".utf8).base64EncodedString()
        #expect(recorder.requests.last?.value(forHTTPHeaderField: "Authorization") == "Basic \(token)")
    }

    @Test("WebDAV surfaces authentication rejection without entering connected state")
    func authenticationRejection() async throws {
        WebDAVTestURLProtocol.setHandler { request in
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 401,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                  ) else {
                throw URLError(.badURL)
            }
            return (response, Data())
        }
        defer { WebDAVTestURLProtocol.setHandler(nil) }

        let adapter = WebDAVDataSourceAdapter(session: Self.makeSession())
        let info = try FileBrowsingDomain.ConnectionInfo.remote(
            sourceType: .webDAV,
            address: "https://media.example.test/library",
            username: "viewer"
        )

        await #expect(throws: WebDAVError.self) {
            try await adapter.connect(with: info)
        }
        guard case .failed = adapter.connectionStatus else {
            Issue.record("WebDAV adapter should remain failed after HTTP 401")
            return
        }
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebDAVTestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated private static let directoryListing = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:multistatus xmlns:d="DAV:">
      <d:response>
        <d:href>/dav/library/</d:href>
        <d:propstat>
          <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/library/Movie%20One.mkv</d:href>
        <d:propstat>
          <d:prop>
            <d:getcontentlength>12345</d:getcontentlength>
            <d:getlastmodified>Wed, 15 Jul 2026 10:00:00 GMT</d:getlastmodified>
            <d:getetag>"movie-one-v3"</d:getetag>
            <d:resourcetype/>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
      <d:response>
        <d:href>/dav/library/Season%201/</d:href>
        <d:propstat>
          <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    </d:multistatus>
    """
}

nonisolated private final class WebDAVRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storage }
    }

    func record(_ request: URLRequest) {
        lock.withLock { storage.append(request) }
    }
}

nonisolated private final class RecordingWebDAVCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let credential: StorageCredential
    private var sourceIDs: [String] = []

    var loadedSourceIDs: [String] {
        lock.withLock { sourceIDs }
    }

    init(credential: StorageCredential) {
        self.credential = credential
    }

    func saveCredential(for sourceID: String, credential: StorageCredential) throws {}

    func loadCredential(for sourceID: String) throws -> StorageCredential? {
        lock.withLock { sourceIDs.append(sourceID) }
        return credential
    }

    func deleteCredential(for sourceID: String) throws {}
}

nonisolated private final class WebDAVTestURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerStore = WebDAVURLProtocolHandlerStore()

    static func setHandler(_ handler: Handler?) {
        handlerStore.set(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handlerStore.get() else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

nonisolated private final class WebDAVURLProtocolHandlerStore: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: WebDAVTestURLProtocol.Handler?

    func set(_ handler: WebDAVTestURLProtocol.Handler?) {
        lock.withLock { self.handler = handler }
    }

    func get() -> WebDAVTestURLProtocol.Handler? {
        lock.withLock { handler }
    }
}
