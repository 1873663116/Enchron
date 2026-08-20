import Foundation
import MediaSource
import Testing
@testable import Emby

@Suite(.serialized)
struct EmbyMediaByteSourceTests {
    @Test("Emby playback routes offset, suffix, and tail reads with its token")
    func routedRangesCarryToken() async throws {
        let recorder = EmbyByteRequestRecorder()
        EmbyByteURLProtocol.setHandler { request in
            recorder.record(request)
            return try Self.byteResponse(for: request)
        }
        defer { EmbyByteURLProtocol.setHandler(nil) }

        let streamURL = try #require(URL(
            string: "https://emby.example.test/Videos/movie/stream.mkv?Static=true&api_key=stale"
        ))
        let source = EmbyMediaByteSource(
            streamURL: streamURL,
            accessToken: "fresh-token",
            contentLength: 10,
            session: Self.makeSession()
        )
        #expect(source.byteStreamAttributes == MediaByteStreamAttributes(
            contentLength: 10,
            supportsSeeking: true,
            isLive: false
        ))
        let server = MediaByteStreamServer()
        let handle = try await server.register(
            source: source,
            filename: "stream.mkv",
            preferredBufferDepth: .automatic
        )
        defer { handle.release() }
        #expect(handle.preferredBufferDepth == .automatic)

        let offset = try await Self.read(handle.url, range: "bytes=2-5")
        let suffix = try await Self.read(handle.url, range: "bytes=-3")
        let tail = try await Self.read(handle.url, range: "bytes=6-")

        #expect(offset == Data("2345".utf8))
        #expect(suffix == Data("789".utf8))
        #expect(tail == Data("6789".utf8))
        #expect(recorder.requests.map { $0.value(forHTTPHeaderField: "Range") } == [
            "bytes=2-5",
            "bytes=7-9",
            "bytes=6-9"
        ])
        #expect(recorder.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "X-Emby-Token") == "fresh-token"
        })
        #expect(recorder.requests.allSatisfy { request in
            guard let url = request.url else { return false }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "api_key" }?
                .value == "fresh-token"
        })
        #expect(source.currentContentLength == 10)
        await server.stopAndWait()
    }

    @Test("Emby byte reads recover length from an unsatisfiable server range")
    func unsatisfiableRangeRecoversLength() async throws {
        EmbyByteURLProtocol.setHandler(Self.byteResponse)
        defer { EmbyByteURLProtocol.setHandler(nil) }

        let streamURL = try #require(URL(
            string: "https://emby.example.test/Videos/movie/stream.mkv"
        ))
        let source = EmbyMediaByteSource(
            streamURL: streamURL,
            accessToken: "token",
            contentLength: 12,
            session: Self.makeSession()
        )

        let read = try await source.read(in: 10..<11)

        #expect(read.data.isEmpty)
        #expect(read.contentLength == 10)
        #expect(read.supportsSeeking)
        #expect(source.currentContentLength == 10)
    }

    @Test("Emby byte reads replace stale metadata with the server range length")
    func staleLengthIsRecovered() async throws {
        EmbyByteURLProtocol.setHandler(Self.byteResponse)
        defer { EmbyByteURLProtocol.setHandler(nil) }

        let streamURL = try #require(URL(
            string: "https://emby.example.test/Videos/movie/stream.mkv"
        ))
        let source = EmbyMediaByteSource(
            streamURL: streamURL,
            accessToken: "token",
            contentLength: 12,
            session: Self.makeSession()
        )

        let read = try await source.read(in: 8..<12)

        #expect(read.data == Data("89".utf8))
        #expect(read.contentLength == 10)
        #expect(read.supportsSeeking)
        #expect(source.currentContentLength == 10)
    }

    private static func read(_ url: URL, range: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(range, forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 206)
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmbyByteURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated private static func byteResponse(
        for request: URLRequest
    ) throws -> (HTTPURLResponse, Data) {
        let bytes = Data("0123456789".utf8)
        let url = try #require(request.url)
        let rangeHeader = try #require(request.value(forHTTPHeaderField: "Range"))
        let bounds = try #require(Self.bounds(from: rangeHeader))
        guard bounds.lowerBound < Int64(bytes.count) else {
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 416,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Range": "bytes */\(bytes.count)"]
            ))
            return (response, Data())
        }

        let end = min(bounds.upperBound - 1, Int64(bytes.count - 1))
        let body = bytes[Int(bounds.lowerBound)...Int(end)]
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 206,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Range": "bytes \(bounds.lowerBound)-\(end)/\(bytes.count)",
                "Content-Length": "\(body.count)"
            ]
        ))
        return (response, Data(body))
    }

    nonisolated private static func bounds(from rangeHeader: String) -> Range<Int64>? {
        guard rangeHeader.hasPrefix("bytes=") else { return nil }
        let bounds = rangeHeader.dropFirst("bytes=".count).split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let inclusiveEnd = Int64(bounds[1]),
              inclusiveEnd >= start else {
            return nil
        }
        return start..<(inclusiveEnd + 1)
    }
}

nonisolated private final class EmbyByteRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storage }
    }

    func record(_ request: URLRequest) {
        lock.withLock { storage.append(request) }
    }
}

nonisolated private final class EmbyByteURLProtocolHandlerStore: @unchecked Sendable {
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

nonisolated private class EmbyByteURLProtocol: URLProtocol {
    typealias Handler = EmbyByteURLProtocolHandlerStore.Handler
    private static let handlerStore = EmbyByteURLProtocolHandlerStore()

    static func setHandler(_ handler: Handler?) {
        handlerStore.set(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handlerStore.get() else {
            client?.urlProtocol(self, didFailWithError: EmbyMediaByteSourceError.invalidResponse)
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
