import Foundation
@testable import MediaSource
import Testing

#if DEBUG
@Suite(.serialized)
struct MediaByteStreamLifecycleTests {
    @Test("retiring one playback stream leaves other streams readable")
    func independentStreamsSurviveRetirement() async throws {
        let source = LifecycleByteRangeSource()
        let first = try await MediaByteStreamServer(readChunkSize: 4)
            .register(source: source, filename: "first.bin")
        let second = try await MediaByteStreamServer(readChunkSize: 4)
            .register(source: source, filename: "second.bin")
        #expect(try await fetchRange("bytes=2-6", from: first.url).body == Data("23456".utf8))
        first.release()
        #expect(try await fetchRange("bytes=2-6", from: second.url).body == Data("23456".utf8))
        second.release()
    }

    @MainActor
    @Test("cancelling preparation releases its streams without touching unrelated content")
    func preparationRetiresOnlyOwnedStreams() async throws {
        let source = LifecycleByteRangeSource()
        let unrelatedServer = MediaByteStreamServer(readChunkSize: 4)
        let unrelated = try await unrelatedServer.register(source: source, filename: "image.bin")
        let preparation = MediaSourcePreparation()
        let playbackServer = MediaByteStreamServer(readChunkSize: 4)
        var resume: CheckedContinuation<Void, Never>?
        var retiredURLs: [URL] = []
        let old = Task {
            try await preparation.resolve {
                let video = try await playbackServer.register(source: source, filename: "video.bin")
                let subtitle = try await playbackServer.register(source: source, filename: "subtitle.bin")
                retiredURLs = [video.url, subtitle.url]
                await withCheckedContinuation { resume = $0 }
                return [video, subtitle]
            }
        }
        while resume == nil { await Task.yield() }
        preparation.cancel()
        resume?.resume()
        do {
            _ = try await old.value
            Issue.record("A retired preparation returned its streams")
        } catch { #expect(error is CancellationError) }
        for url in retiredURLs {
            do {
                _ = try await fetchRange("bytes=2-6", from: url)
                Issue.record("The retired playback listener still accepts requests")
            } catch {
                #expect((error as? URLError)?.code == .cannotConnectToHost)
            }
        }
        #expect(try await fetchRange("bytes=2-6", from: unrelated.url).body == Data("23456".utf8))
        unrelated.release()
        await playbackServer.stopAndWait()
        await unrelatedServer.stopAndWait()
    }

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

    @Test("an active playback endpoint bundle moves to one fresh listener generation")
    func activeEndpointBundleRefreshesTogether() async throws {
        let source = LifecycleByteRangeSource()
        let server = MediaByteStreamServer(readChunkSize: 4)
        let video = try await server.register(source: source, filename: "video.bin")
        let subtitle = try await server.register(source: source, filename: "subtitle.vtt")

        let refreshed = try await MediaByteStreamHandle.refreshing(
            [video, subtitle],
            restartingListeners: true
        )
        #expect(refreshed.count == 2)
        #expect(refreshed[0].url != video.url)
        #expect(refreshed[1].url != subtitle.url)

        video.release()
        subtitle.release()

        #expect(
            try await fetchRange("bytes=2-6", from: refreshed[0].url).body
                == Data("23456".utf8)
        )
        #expect(
            try await fetchRange("bytes=2-6", from: refreshed[1].url).body
                == Data("23456".utf8)
        )

        refreshed.forEach { $0.release() }
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

private final class SimulatedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    private var step: Double

    init(step: Double) {
        self.step = step
    }

    func now() -> Double {
        lock.withLock { value }
    }

    func advance() {
        lock.withLock { value += step }
    }

    func setStep(_ next: Double) {
        lock.withLock { step = next }
    }
}

@Suite(.serialized)
struct CapacityProbeTests {
    @Test("block size derives from bandwidth and latency")
    func blockSizeDerivesFromBandwidthAndLatency() async {
        let clock = SimulatedClock(step: 0.42)
        let pipeline = MediaReadPipeline(
            configuration: MediaReadPipeline.Configuration(cacheCapacityBytes: 512 * 1_024 * 1_024),
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advance()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        _ = await pipeline.measureLatency()
        let snapshot = await pipeline.snapshot()
        let expected = Double(snapshot.throughputBytesPerSecond) * 0.42
        #expect(snapshot.blockSize > 64 * 1_024)
        #expect(Double(snapshot.blockSize) <= 512 * 1_024 * 1_024 / 8)
        if expected > 64 * 1_024 {
            #expect(abs(Double(snapshot.blockSize) - expected) < expected * 0.5 + 1)
        }
    }

    @Test("prefetch never exceeds what the cache can hold")
    func prefetchStaysWithinCache() async {
        let clock = SimulatedClock(step: 1.0)
        let pipeline = MediaReadPipeline(
            configuration: MediaReadPipeline.Configuration(
                blockSize: 256 * 1_024,
                cacheCapacityBytes: 16 * 1_024 * 1_024
            ),
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advance()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        _ = await pipeline.measureLatency()
        let snapshot = await pipeline.snapshot()
        let block = snapshot.blockSize
        #expect(block > 0)
        #expect(Int64(snapshot.prefetchBlocks) * block <= 16 * 1_024 * 1_024)
    }

    @Test("prefetch depth derives from latency not a fixed window")
    func prefetchDepthDerivesFromLatency() async {
        let clock = SimulatedClock(step: 0.42)
        let pipeline = MediaReadPipeline(
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advance()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        _ = await pipeline.measureLatency()
        let snapshot = await pipeline.snapshot()
        #expect(snapshot.prefetchBlocks >= 1)
        #expect(snapshot.prefetchBlocks <= 4)
    }

    @Test("capacity floor keeps the slowest probe")
    func capacityFloorKeepsSlowestProbe() async {
        let clock = SimulatedClock(step: 0.262144)
        let pipeline = MediaReadPipeline(
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advance()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        _ = await pipeline.measureCapacity(blocks: 2)
        let fast = await pipeline.snapshot().throughputBytesPerSecond
        #expect(fast > 10_000_000)
        clock.setStep(0.786432)
        _ = await pipeline.measureCapacity(blocks: 2)
        let slow = await pipeline.snapshot().throughputBytesPerSecond
        #expect(slow < fast)
    }

    @Test("latency probe returns simulated round trip")
    func latencyProbeReturnsRoundTrip() async {
        let clock = SimulatedClock(step: 0.12)
        let pipeline = MediaReadPipeline(
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advance()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        let latency = await pipeline.measureLatency()
        #expect(latency != nil)
        guard let latency else { return }
        #expect(abs(latency - 0.12) < 0.02)
    }

    @Test("capacity probe divides bytes by simulated wall time")
    func capacityProbeDividesBytesByTime() async {
        let clock = SimulatedClock(step: 0.524288)
        let pipeline = MediaReadPipeline(
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advance()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        let rate = await pipeline.measureCapacity(blocks: 4)
        #expect(rate != nil)
        guard let rate else { return }
        #expect(abs(rate - 8_000_000) < 8_000_000 * 0.05)
    }
}

@Suite(.serialized)
struct SourceProbeTests {
    @Test("probe separates latency and throughput from mixed sizes")
    func separatesLatencyAndThroughput() {
        var probe = MediaReadPipeline.SourceProbe()
        let latency = 0.3
        let throughput = 8_000_000.0
        var cursor = 0.0
        for size in [4_096, 262_144, 1_048_576, 4_194_304] {
            let duration = latency + Double(size) / throughput
            probe.record(bytes: size, start: cursor, end: cursor + duration)
            cursor += duration
        }
        let estimate = probe.estimate
        #expect(estimate != nil)
        guard let estimate else { return }
        #expect(abs(estimate.latencySeconds - latency) < latency * 0.1)
        #expect(abs(estimate.throughputBytesPerSecond - throughput) < throughput * 0.1)
        #expect(estimate.sampleCount == 4)
    }

    @Test("probe separates latency and throughput across concurrency levels")
    func separatesAcrossConcurrencyLevels() {
        var probe = MediaReadPipeline.SourceProbe()
        let latency = 0.3
        let throughput = 8_000_000.0
        let block = 4_194_304.0
        let sequential = latency + block / throughput
        probe.record(bytes: Int(block), start: 0, end: sequential)
        let parallel = latency + block * 2 / throughput
        probe.record(bytes: Int(block), start: 1, end: 1 + parallel)
        probe.record(bytes: Int(block), start: 1, end: 1 + parallel)
        let estimate = probe.estimate
        #expect(estimate != nil)
        guard let estimate else { return }
        #expect(abs(estimate.latencySeconds - latency) < latency * 0.1)
        #expect(abs(estimate.throughputBytesPerSecond - throughput) < throughput * 0.1)
    }

    @Test("small latency-dominated reads do not distort throughput")
    func smallReadsDoNotDistortThroughput() {
        var probe = MediaReadPipeline.SourceProbe()
        let latency = 0.3
        let throughput = 8_000_000.0
        let large = 4_194_304.0
        var cursor = 0.0
        let largeDuration = latency + large / throughput
        probe.record(bytes: Int(large), start: cursor, end: cursor + largeDuration)
        cursor += largeDuration
        for _ in 0..<3 {
            let duration = latency + 4_096.0 / throughput
            probe.record(bytes: 4_096, start: cursor, end: cursor + duration)
            cursor += duration
        }
        guard let estimate = probe.estimate else {
            Issue.record("probe returned no estimate")
            return
        }
        #expect(abs(estimate.throughputBytesPerSecond - throughput) < throughput * 0.2)
        #expect(abs(estimate.latencySeconds - latency) < latency * 0.2)
    }

    @Test("recent rate measures the delivery window")
    func recentRateMeasuresWindow() {
        var probe = MediaReadPipeline.SourceProbe()
        probe.record(bytes: 4_194_304, start: 0, end: 0.524)
        probe.record(bytes: 4_194_304, start: 0.524, end: 1.048)
        let rate = probe.recentRate(window: 10, now: 1.048)
        #expect(rate != nil)
        guard let rate else { return }
        #expect(abs(rate - 8_000_000) < 8_000_000 * 0.05)
    }

    @Test("recent rate ignores samples outside the window")
    func recentRateIgnoresOldSamples() {
        var probe = MediaReadPipeline.SourceProbe()
        probe.record(bytes: 8_388_608, start: 0, end: 1)
        probe.record(bytes: 4_194_304, start: 10, end: 10.524)
        let rate = probe.recentRate(window: 2, now: 10.524)
        #expect(rate != nil)
        guard let rate else { return }
        #expect(abs(rate - 8_000_000) < 8_000_000 * 0.05)
    }

    @Test("probe reports error rate")
    func reportsErrorRate() {
        var probe = MediaReadPipeline.SourceProbe()
        probe.record(bytes: 1_024, seconds: 0.2)
        probe.record(bytes: 2_048, seconds: 0.3)
        probe.recordFailure()
        probe.recordFailure()
        #expect(probe.estimate?.errorRate == 0.5)
    }

    @Test("identical sizes fall back to aggregate throughput")
    func identicalSizesUseAggregateThroughput() {
        var probe = MediaReadPipeline.SourceProbe()
        for index in 0..<4 {
            let start = Double(index) * 0.431
            probe.record(bytes: 1_048_576, start: start, end: start + 0.431)
        }
        let estimate = probe.estimate
        #expect(estimate != nil)
        guard let estimate else { return }
        let expected = 4.0 * 1_048_576.0 / (4.0 * 0.431)
        #expect(abs(estimate.throughputBytesPerSecond - expected) < expected * 0.1)
        #expect(estimate.latencySeconds >= 0)
        #expect(estimate.latencySeconds < 0.1)
    }

    @Test("probe needs at least two valid samples")
    func needsTwoSamples() {
        var probe = MediaReadPipeline.SourceProbe()
        probe.record(bytes: 1_024, seconds: 0.2)
        #expect(probe.estimate == nil)
        probe.recordFailure()
        #expect(probe.estimate == nil)
    }
}
#endif

@Suite(.serialized)
struct MediaReadPipelineTests {
    @Test("a cached block serves a second read without another backend read")
    func cachedBlockServesOnce() async throws {
        let source = CountingRangeSource(length: 4 * 1_024 * 1_024)
        let pipeline = MediaReadPipeline(
            configuration: .init(
                blockSize: 262_144,
                maxConcurrentReads: 2,
                maxPrefetchBlocks: 1,
                prefetchTargetSeconds: 0.05
            ),
            contentLength: 4 * 1_024 * 1_024,
            backendRead: { range in try await source.read(in: range) }
        )
        let first = try await pipeline.read(0..<1_024)
        let second = try await pipeline.read(0..<1_024)
        #expect(first.data == second.data)
        #expect(first.contentLength == source.byteStreamAttributes.contentLength)
        #expect(source.readCount(of: 0..<262_144) == 1)
    }

    @Test("concurrent reads of one block share a single backend read")
    func concurrentReadsDeduplicate() async throws {
        let source = CountingRangeSource(length: 4 * 1_024 * 1_024)
        let pipeline = MediaReadPipeline(
            configuration: .init(
                blockSize: 262_144,
                maxConcurrentReads: 4,
                maxPrefetchBlocks: 1,
                prefetchTargetSeconds: 0.05
            ),
            contentLength: 4 * 1_024 * 1_024,
            backendRead: { range in try await source.read(in: range) }
        )
        async let first = pipeline.read(0..<1_024)
        async let second = pipeline.read(1_024..<2_048)
        _ = try await (first, second)
        #expect(source.readCount(of: 0..<262_144) == 1)
    }

    @Test("a read crossing a block boundary assembles both blocks in order")
    func crossBlockReadAssembles() async throws {
        let source = CountingRangeSource(length: 4 * 1_024 * 1_024)
        let pipeline = MediaReadPipeline(
            configuration: .init(
                blockSize: 4_096,
                maxConcurrentReads: 2,
                maxPrefetchBlocks: 1,
                prefetchTargetSeconds: 0.05
            ),
            contentLength: 4 * 1_024 * 1_024,
            backendRead: { range in try await source.read(in: range) }
        )
        let read = try await pipeline.read(4_000..<4_200)
        let expected = Data((4_000..<4_200).map { UInt8(truncatingIfNeeded: $0) })
        #expect(read.data == expected)
        #expect(source.readCount(of: 0..<4_096) == 1)
        #expect(source.readCount(of: 4_096..<8_192) == 1)
    }

    @Test("a miss schedules prefetch for the blocks that follow")
    func missSchedulesPrefetch() async throws {
        let source = CountingRangeSource(length: 4 * 1_024 * 1_024)
        let pipeline = MediaReadPipeline(
            configuration: .init(
                blockSize: 4_096,
                maxConcurrentReads: 2,
                maxPrefetchBlocks: 2,
                prefetchTargetSeconds: 0.05
            ),
            contentLength: 4 * 1_024 * 1_024,
            backendRead: { range in try await source.read(in: range) }
        )
        _ = try await pipeline.read(0..<1_024)
        try await Task.sleep(for: .milliseconds(150))
        #expect(source.readCount >= 2)
        #expect(await pipeline.snapshot().cachedBlocks >= 2)
    }
}

private final class CountingRangeSource: MediaByteRangeSource, @unchecked Sendable {
    let byteStreamAttributes: MediaByteStreamAttributes
    private let lock = NSLock()
    private var ranges: [Range<Int64>] = []

    init(length: Int64) {
        byteStreamAttributes = MediaByteStreamAttributes(
            contentLength: length,
            supportsSeeking: true,
            isLive: false
        )
    }

    var readCount: Int { lock.withLock { ranges.count } }

    func readCount(of range: Range<Int64>) -> Int {
        lock.withLock { ranges.filter { $0 == range }.count }
    }

    func read(in range: Range<Int64>) async throws -> MediaByteRangeRead {
        lock.withLock { ranges.append(range) }
        let data = Data((range.lowerBound..<range.upperBound).map { UInt8(truncatingIfNeeded: $0) })
        return MediaByteRangeRead(
            data: data,
            contentLength: byteStreamAttributes.contentLength,
            supportsSeeking: true
        )
    }
}
