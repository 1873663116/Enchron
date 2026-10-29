#if DEBUG
import Foundation
import Testing

@testable import MediaSource

private final class OutlierClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    private var step: Double
    private var calls = 0

    init(step: Double) {
        self.step = step
    }

    func now() -> Double {
        lock.withLock { value }
    }

    func advanceCall() {
        lock.withLock {
            value += calls < 5 ? step : step / 3
            calls += 1
        }
    }
}

@Suite(.serialized)
struct CapacityProbeOutlierTests {
    @Test("a faster second round does not raise the measured capacity")
    func hotRoundIsDiscarded() async throws {
        let blockSize: Int64 = 4 * 1_024 * 1_024
        let clock = OutlierClock(step: 0.5)
        let pipeline = MediaReadPipeline(
            configuration: MediaReadPipeline.Configuration(blockSize: blockSize),
            contentLength: 512 * 1_024 * 1_024,
            clock: { clock.now() },
            backendRead: { range in
                clock.advanceCall()
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        _ = await pipeline.measureLatency()
        let measuredBlock = await pipeline.snapshot().blockSize
        guard let rate = await pipeline.measureCapacity(blocks: 4) else {
            Issue.record("capacity probe returned no value")
            return
        }
        let coldRate = Double(measuredBlock) * 4 / (0.5 * 4)
        #expect(abs(rate - coldRate) / coldRate < 0.05, "rate \(rate) cold \(coldRate)")
    }
}
#endif
