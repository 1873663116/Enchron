import Foundation
import MediaSource
import Testing
@testable import Emby

@Suite(.serialized)
struct EmbyMediaSourceReadFailureTests {
    @Test("HTTP read causes map to the shared typed failure contract")
    func httpFailures() async throws {
        let cases: [(Int, MediaSourceReadFailure)] = [
            (401, .accessDenied),
            (404, .resourceMissing),
            (503, .transportInterrupted)
        ]

        for (status, expected) in cases {
            EmbyReadFailureURLProtocol.setHandler { request in
                guard let url = request.url else { throw URLError(.badURL) }
                let response = try #require(HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                ))
                return (response, Data())
            }
            let source = try makeSource()

            await #expect(throws: expected) {
                try await source.read(in: 0..<1)
            }
        }
        EmbyReadFailureURLProtocol.setHandler(nil)
    }

    @Test("TLS transport causes map without localized text inspection")
    func tlsFailure() async throws {
        EmbyReadFailureURLProtocol.setHandler { _ in
            throw URLError(.secureConnectionFailed)
        }
        defer { EmbyReadFailureURLProtocol.setHandler(nil) }

        let source = try makeSource()

        await #expect(throws: MediaSourceReadFailure.transportInterrupted) {
            try await source.read(in: 0..<1)
        }
    }

    @Test("malformed byte responses map to invalid data")
    func malformedResponse() async throws {
        EmbyReadFailureURLProtocol.setHandler { request in
            guard let url = request.url else { throw URLError(.badURL) }
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ))
            return (response, Data([0]))
        }
        defer { EmbyReadFailureURLProtocol.setHandler(nil) }

        let source = try makeSource()

        await #expect(throws: MediaSourceReadFailure.invalidData) {
            try await source.read(in: 0..<1)
        }
    }

    private func makeSource() throws -> EmbyMediaByteSource {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmbyReadFailureURLProtocol.self]
        return EmbyMediaByteSource(
            streamURL: try #require(URL(string: "https://emby.example.test/video.mkv")),
            accessToken: "test-token",
            contentLength: 1,
            session: URLSession(configuration: configuration)
        )
    }
}

nonisolated private final class EmbyReadFailureHandlerStore: @unchecked Sendable {
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

nonisolated private class EmbyReadFailureURLProtocol: URLProtocol {
    typealias Handler = EmbyReadFailureHandlerStore.Handler
    private static let handlerStore = EmbyReadFailureHandlerStore()

    static func setHandler(_ handler: Handler?) {
        handlerStore.set(handler)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handlerStore.get() else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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
