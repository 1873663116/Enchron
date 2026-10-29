#if DEBUG
import Foundation
import Testing

@testable import MediaSource

private final class StabilityClock: @unchecked Sendable {
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
struct BlockSizeStabilityTests {
    @Test("block size never changes while the cache holds data")
    func blockSizeIsStableWithCachedData() async throws {
        let clock = StabilityClock(step: 0.4)
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
        let block = await pipeline.snapshot().blockSize
        _ = try await pipeline.read(0..<block)
        #expect(await pipeline.snapshot().cachedBytes > 0)
        clock.setStep(0.05)
        _ = await pipeline.measureLatency()
        #expect(await pipeline.snapshot().blockSize == block)
    }
}
#endif
