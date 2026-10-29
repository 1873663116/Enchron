#if DEBUG
import Foundation
import Testing

@testable import MediaSource

private final class SteppedClock: @unchecked Sendable {
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
struct CapacityProbeLatestTests {
    @Test("planning follows the latest probe instead of the smallest")
    func planningFollowsLatestProbe() async throws {
        let clock = SteppedClock(step: 0.5)
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
        guard let slow = await pipeline.measureCapacity(blocks: 2) else {
            Issue.record("first probe returned no value")
            return
        }
        clock.setStep(0.05)
        guard let fast = await pipeline.measureCapacity(blocks: 2) else {
            Issue.record("second probe returned no value")
            return
        }
        let planned = await pipeline.snapshot().throughputBytesPerSecond
        #expect(fast > slow, "fast \(fast) slow \(slow)")
        #expect(abs(planned - fast) / fast < 0.05, "planned \(planned) fast \(fast) slow \(slow)")
    }
}
#endif
