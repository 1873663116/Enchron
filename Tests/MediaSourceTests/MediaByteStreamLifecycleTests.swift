import Foundation
import MediaSource
import Testing

#if DEBUG
@Suite(.serialized)
struct MediaByteStreamLifecycleTests {
    @Test("background teardown permits immediate reopen before old handles release")
    func backgroundTeardownPermitsImmediateReopen() async throws {
        let source = LifecycleByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 4)
        let before = try await server.register(source: source, filename: "before.bin")
        let initial = try await fetchRange("bytes=2-6", from: before.url)
        #expect(initial.body == Data("23456".utf8))

        server.stop()
        server.stop()

        let after = try await server.register(source: source, filename: "after.bin")
        before.release()
        for _ in 0..<3 {
            let served = try await fetchRange("bytes=2-6", from: after.url)
            #expect(served.statusCode == 206)
            #expect(served.body == Data("23456".utf8))
        }
        after.release()
        await server.stopAndWait()
    }


}

private final class LifecycleByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: 10,
        supportsSeeking: true,
        isLive: false
    )

    private let payload = Data("0123456789".utf8)

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let count = Int64(payload.count)
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        return MediaByteRangeRead(
            data: Data(payload[Int(lower)..<Int(upper)]),
            contentLength: count,
            supportsSeeking: true
        )
    }
}

private struct LifecycleObservation: Sendable {
    let statusCode: Int
    let body: Data
}

private func fetchRange(_ value: String, from url: URL) async throws -> LifecycleObservation {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 3
    configuration.timeoutIntervalForResource = 3
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: url)
    request.setValue(value, forHTTPHeaderField: "Range")
    let (body, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    return LifecycleObservation(statusCode: http.statusCode, body: body)
}
#endif
