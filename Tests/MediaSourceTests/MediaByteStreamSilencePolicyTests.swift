import Foundation
import MediaSource
import Testing

#if DEBUG
@Suite(.serialized)
struct MediaByteStreamSilencePolicyTests {
    @Test("a slow read inside the silence window succeeds without retrying")
    func slowReadInsideWindowSucceeds() async throws {
        let source = GatedByteRangeSource()
        source.setResponseDelay(nanoseconds: 100_000_000)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "slow.bin")
        defer { stream.release() }

        let response = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(response.statusCode == 206)
        #expect(response.body == Data("0123".utf8))
        #expect(source.readCount == 1)
        await server.stopAndWait()
    }

    @Test("a silent read is retried once and succeeds when the retry answers")
    func silentReadRetriesOnce() async throws {
        let source = GatedByteRangeSource()
        source.stallNext(1)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "retry.bin")
        defer { stream.release() }

        let response = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(response.statusCode == 206)
        #expect(response.body == Data("0123".utf8))
        #expect(source.readCount == 2)
        await server.stopAndWait()
    }

    @Test("a source that stays silent through the retry fails the request")
    func deadSourceFailsAfterRetryExhausted() async throws {
        let source = GatedByteRangeSource()
        source.setStallAll(true)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "dead.bin")
        defer { stream.release() }

        let response = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(response.statusCode == 502)
        #expect(source.readCount == 2)
        await server.stopAndWait()
    }

    @Test("a degraded registration fails fast instead of waiting a full window")
    func degradedRegistrationFailsFast() async throws {
        let source = GatedByteRangeSource()
        source.setStallAll(true)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "dead.bin")
        defer { stream.release() }

        let first = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(first.statusCode == 502)
        #expect(source.readCount == 2)

        let started = ContinuousClock.now
        let second = try await fetchRange("bytes=0-3", from: stream.url)
        let elapsed = ContinuousClock.now - started
        #expect(second.statusCode == 502)
        #expect(source.readCount == 3)
        #expect(elapsed < .milliseconds(400))
        await server.stopAndWait()
    }

    @Test("a successful read restores the normal retry budget")
    func successClearsDegradedMode() async throws {
        let source = GatedByteRangeSource()
        source.setStallAll(true)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "flaky.bin")
        defer { stream.release() }

        let dead = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(dead.statusCode == 502)
        #expect(source.readCount == 2)

        source.setStallAll(false)
        let recovered = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(recovered.statusCode == 206)
        #expect(recovered.body == Data("0123".utf8))
        #expect(source.readCount == 3)

        source.setStallAll(true)
        let stalledAgain = try await fetchRange("bytes=4-7", from: stream.url)
        #expect(stalledAgain.statusCode == 502)
        #expect(
            source.readCount == 5,
            "normal mode restored: two full-window attempts, not one degraded read"
        )
        await server.stopAndWait()
    }

    private func makeServer() -> MediaByteStreamServer {
        MediaByteStreamServer(
            readChunkSize: 4,
            silentReadTimeout: .milliseconds(250),
            silentReadRetryLimit: 1,
            degradedReadTimeout: .milliseconds(60)
        )
    }
}

private final class GatedByteRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes = MediaByteStreamAttributes(
        contentLength: 10,
        supportsSeeking: true,
        isLive: false
    )

    private let payload = Data("0123456789".utf8)
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var readCount = 0
        var stallRemainingCalls = 0
        var stallAll = false
        var responseDelayNanoseconds: UInt64 = 0
    }

    var readCount: Int { lock.withLock { state.readCount } }

    func stallNext(_ count: Int) {
        lock.withLock { state.stallRemainingCalls += count }
    }

    func setStallAll(_ flag: Bool) {
        lock.withLock { state.stallAll = flag }
    }

    func setResponseDelay(nanoseconds: UInt64) {
        lock.withLock { state.responseDelayNanoseconds = nanoseconds }
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let (stalls, delay) = lock.withLock { () -> (Bool, UInt64) in
            state.readCount += 1
            let stalls = state.stallAll || state.stallRemainingCalls > 0
            if state.stallRemainingCalls > 0 { state.stallRemainingCalls -= 1 }
            return (stalls, state.responseDelayNanoseconds)
        }
        if stalls {
            try await Task.sleep(nanoseconds: 600_000_000_000)
        }
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
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

private struct SilencePolicyObservation: Sendable {
    let statusCode: Int
    let body: Data
}

private func fetchRange(
    _ value: String,
    from url: URL
) async throws -> SilencePolicyObservation {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 5
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: url)
    request.setValue(value, forHTTPHeaderField: "Range")
    let (body, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    return SilencePolicyObservation(statusCode: http.statusCode, body: body)
}
#endif
