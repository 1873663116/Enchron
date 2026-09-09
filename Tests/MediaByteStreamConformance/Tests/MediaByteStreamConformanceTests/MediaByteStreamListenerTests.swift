import Foundation
import MediaSource
import Testing

#if DEBUG
@Suite(.serialized)
struct MediaByteStreamListenerTests {
    @Test("a registration after the listener died serves from a new listener")
    func aRegistrationAfterTheListenerDiedServesFromANewListener() async throws {
        let source = ListenerByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 4)
        let before = try await server.register(source: source, filename: "before.bin")
        let served = try await fetchRange("bytes=2-6", from: before.url)
        #expect(served.statusCode == 206)
        #expect(served.body == Data("23456".utf8))

        await server.debugCancelListener()

        do {
            let after = try await server.register(source: source, filename: "after.bin")
            let reserved = try await fetchRange("bytes=2-6", from: after.url)
            #expect(reserved.statusCode == 206)
            #expect(reserved.body == Data("23456".utf8))
            after.release()
        } catch {
            Issue.record(
                "a registration made after the listener died is unreachable at \(error)"
            )
        }

        before.release()
        await server.stopAndWait()
    }
}

private final class ListenerByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
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

private struct ListenerObservation: Sendable {
    let statusCode: Int
    let body: Data
}

private func fetchRange(_ value: String, from url: URL) async throws -> ListenerObservation {
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
    return ListenerObservation(statusCode: http.statusCode, body: body)
}
#endif
