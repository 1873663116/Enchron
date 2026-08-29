import CoreGraphics
import Foundation
import ImageIO
import MediaSource
import Synchronization
import Testing
@testable import Emby

#if DEBUG
@Suite("Emby artwork evidence loader", .serialized)
struct EmbyArtworkEvidenceLoaderTests {
    @Test("prefetch stores into the display cache and a repeat load performs no second request")
    func prefetchAndDisplayShareOneCachePath() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ArtworkStore(debugRootURL: root)
        ArtworkEvidenceURLProtocol.reset(data: try jpegData())
        defer { ArtworkEvidenceURLProtocol.reset(data: Data()) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArtworkEvidenceURLProtocol.self]
        configuration.urlCache = nil
        let loader = EmbyArtworkEvidenceLoader(
            store: store,
            session: URLSession(configuration: configuration)
        )
        let url = try #require(URL(
            string: "http://example.test/Items/episode/Images/Primary?api_key=secret&Tag=tag-a&MaxWidth=420"
        ))
        let request = EmbyArtworkLoadRequest(
            itemID: EmbyItemID(rawValue: "episode"),
            imageType: .primary,
            imageTag: EmbyImageTag(rawValue: "tag-a"),
            url: url
        )

        let first = await loader.load(request)
        let cacheKey = ArtworkKey(remoteImageURL: url)
        let displayed = store.image(for: cacheKey)
        let second = await loader.load(request)

        #expect(first.cacheHit.value == false)
        #expect(first.network.value?.statusCode == 200)
        #expect(first.network.value?.responseDigest.hasPrefix("sha256:") == true)
        #expect(first.persistedCache.value?.artworkKey == cacheKey.debugStorageKey)
        #expect(first.loopbackHitCount.value == 0)
        #expect(first.sanitizedRequestURL == "http://example.test/Items/episode/Images/Primary?Tag=tag-a&MaxWidth=420")
        #expect(first.cacheKey == cacheKey.debugStorageKey)
        #expect(displayed != nil)
        #expect(second.cacheHit.value == true)
        #expect(second.network.status == .notApplicable)
        #expect(second.persistedCache.value?.artworkKey == cacheKey.debugStorageKey)
        #expect(second.loopbackHitCount.status == .notApplicable)
        #expect(ArtworkEvidenceURLProtocol.requestCount == 1)
        #expect(first.sanitizedRequestURL?.contains("secret") == false)
    }
}

private final class ArtworkEvidenceURLProtocolState: @unchecked Sendable {
    struct Value: Sendable {
        var data = Data()
        var requestCount = 0
    }

    let value = Mutex(Value())
}

private final class ArtworkEvidenceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = ArtworkEvidenceURLProtocolState()

    static var requestCount: Int { state.value.withLock(\.requestCount) }

    static func reset(data: Data) {
        state.value.withLock {
            $0.data = data
            $0.requestCount = 0
        }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.state.value.withLock { state in
            state.requestCount += 1
            return state.data
        }
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "image/jpeg"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func jpegData() throws -> Data {
    let context = try #require(CGContext(
        data: nil,
        width: 4,
        height: 4,
        bitsPerComponent: 8,
        bytesPerRow: 16,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data,
        "public.jpeg" as CFString,
        1,
        nil
    ))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
#endif
