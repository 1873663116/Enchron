import Foundation
@testable import MediaSource
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

    @Test("a transient failure is retried and then succeeds")
    func transientFailureRetries() async throws {
        let source = GatedByteRangeSource()
        source.failNext(1)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "flaky.bin")
        defer { stream.release() }

        let response = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(response.statusCode == 206)
        #expect(response.body == Data("0123".utf8))
        #expect(source.readCount == 2)
        await server.stopAndWait()
    }

    @Test("an HTTP 500 from the source is retried and then succeeds")
    func httpServerErrorRetries() async throws {
        let source = GatedByteRangeSource()
        source.failHttp(500, times: 1)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "error500.bin")
        defer { stream.release() }

        let response = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(response.statusCode == 206)
        #expect(response.body == Data("0123".utf8))
        #expect(source.readCount == 2)
        await server.stopAndWait()
    }

    @Test("repeated failure opens the breaker and fails without touching the source")
    func breakerOpensAfterRepeatedFailure() async throws {
        let source = GatedByteRangeSource()
        source.failAll(true)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "broken.bin")
        defer { stream.release() }

        let first = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(first.statusCode >= 500)
        let afterFirst = source.readCount
        let second = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(second.statusCode >= 500)
        #expect(source.readCount == afterFirst)
        await server.stopAndWait()
    }

    @Test("the breaker closes again after the cooldown when a read succeeds")
    func breakerRecoversAfterCooldown() async throws {
        let source = GatedByteRangeSource()
        source.failAll(true)
        let server = makeServer()
        let stream = try await server.register(source: source, filename: "recover.bin")
        defer { stream.release() }

        let failed = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(failed.statusCode >= 500)
        source.failAll(false)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let recovered = try await fetchRange("bytes=0-3", from: stream.url)
        #expect(recovered.statusCode == 206)
        #expect(recovered.body == Data("0123".utf8))
        await server.stopAndWait()
    }

    @Test("clearing the throttle releases a waiting consumer")
    func throttleReleasesConsumer() async throws {
        let throttle = MediaByteStreamServer.SourceThrottle()
        throttle.configure(bytesPerSecond: 1)
        let waiting = Task { await throttle.consume(100_000) }
        try await Task.sleep(nanoseconds: 200_000_000)
        let startedAt = Date()
        throttle.configure(bytesPerSecond: 0)
        await waiting.value
        #expect(Date().timeIntervalSince(startedAt) < 0.5)
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
        let cached = try await fetchRange("bytes=4-7", from: stream.url)
        #expect(cached.statusCode == 206)
        #expect(cached.body == Data("4567".utf8))
        #expect(source.readCount == 3)
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
        var failRemainingCalls = 0
        var failAllReads = false
        var httpFailure: Int?
        var responseDelayNanoseconds: UInt64 = 0
    }

    var readCount: Int { lock.withLock { state.readCount } }

    func stallNext(_ count: Int) {
        lock.withLock { state.stallRemainingCalls += count }
    }

    func setStallAll(_ flag: Bool) {
        lock.withLock { state.stallAll = flag }
    }

    func failHttp(_ status: Int, times: Int) {
        lock.withLock {
            state.httpFailure = status
            state.failRemainingCalls += times
        }
    }

    func failAll(_ flag: Bool) {
        lock.withLock { state.failAllReads = flag }
    }

    func failNext(_ count: Int) {
        lock.withLock { state.failRemainingCalls += count }
    }

    func setResponseDelay(nanoseconds: UInt64) {
        lock.withLock { state.responseDelayNanoseconds = nanoseconds }
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        let shouldFail = lock.withLock { () -> Bool in
            if state.failAllReads {
                state.readCount += 1
                return true
            }
            if state.failRemainingCalls > 0 {
                state.failRemainingCalls -= 1
                state.readCount += 1
                return true
            }
            return false
        }
        if shouldFail {
            if let status = lock.withLock({ state.httpFailure }),
               let failure = MediaSourceReadFailure(httpStatusCode: status) {
                throw failure
            }
            throw MediaSourceReadFailure.transportInterrupted
        }
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
