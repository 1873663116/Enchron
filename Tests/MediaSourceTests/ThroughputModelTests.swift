#if DEBUG
import Foundation
import Testing

@testable import MediaSource

private final class ThroughputClock: @unchecked Sendable {
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
struct ThroughputModelTests {
    @Test("demand throughput reaches ninety-five percent of bandwidth")
    func demandThroughputReachesBound() async throws {
        let grid: [(bandwidth: Double, latency: Double)] =
            [1, 2, 8, 20, 50].flatMap { bandwidth in
                [0.005, 0.05, 0.3].map { latency in
                    (Double(bandwidth) * 1_000_000, latency)
                }
            }
        for point in grid {
            let clock = ThroughputClock(step: point.latency)
            final class Range: @unchecked Sendable {
                private let lock = NSLock()
                private var end: Int64 = 0
                func set(_ next: Int64) {
                    lock.withLock { end = next }
                }
                func contains(_ offset: Int64) -> Bool {
                    lock.withLock { offset < end }
                }
            }
            let demandRange = Range()
            let pipeline = MediaReadPipeline(
                contentLength: 512 * 1_024 * 1_024,
                clock: { clock.now() },
                backendRead: { range in
                    if demandRange.contains(range.lowerBound) {
                        clock.advance()
                    }
                    return MediaByteRangeRead(
                        data: Data(count: Int(range.count)),
                        contentLength: nil,
                        supportsSeeking: true
                    )
                }
            )
            _ = await pipeline.measureLatency()
            let block = await pipeline.snapshot().blockSize
            let metadataEnd = block * 4
            demandRange.set(metadataEnd)
            clock.setStep(Double(block) / point.bandwidth)
            let startedAt = clock.now()
            _ = try await pipeline.read(0..<metadataEnd)
            let elapsed = clock.now() - startedAt
            #expect(elapsed > 0, "B=\(point.bandwidth)")
            guard elapsed > 0 else { continue }
            let rate = Double(metadataEnd) / elapsed
            #expect(
                rate >= point.bandwidth * 0.95,
                "B=\(point.bandwidth) L=\(point.latency): rate \(rate)"
            )
            let openBound = 1.25 * (point.latency + Double(metadataEnd) / point.bandwidth)
            #expect(
                elapsed <= openBound,
                "B=\(point.bandwidth) L=\(point.latency): open \(elapsed) bound \(openBound)"
            )
        }
    }
}
#endif
