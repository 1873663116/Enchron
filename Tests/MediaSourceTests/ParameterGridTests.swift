#if DEBUG
import Foundation
import Testing

@testable import MediaSource

private final class GridClock: @unchecked Sendable {
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
struct ParameterGridTests {
    @Test("derived parameters follow the model across the grid")
    func derivedParametersFollowGrid() async {
        let cache = 64 * 1_024 * 1_024
        let initialThroughput = 10_000_000.0
        let bandwidths = [1, 2, 8, 20, 50].map { Double($0) * 1_000_000 }
        let latencies = [0.005, 0.05, 0.3]
        for bandwidth in bandwidths {
            for latency in latencies {
                let block = min(max(initialThroughput * latency, 64 * 1_024), Double(cache) / 8)
                let clock = GridClock(step: latency)
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
                clock.setStep(block / bandwidth)
                _ = await pipeline.measureCapacity(blocks: 1)
                let snapshot = await pipeline.snapshot()

                let blockSeconds = block / bandwidth
                let concurrency = min(
                    max(Int((1 + latency / blockSeconds).rounded(.up)), 2),
                    8
                )
                #expect(
                    snapshot.blockSize == Int64(block),
                    "block at B=\(bandwidth) L=\(latency)"
                )
                #expect(
                    snapshot.concurrency >= concurrency,
                    """
                    concurrency at B=\(bandwidth) L=\(latency): got \(snapshot.concurrency) \
                    want at least \(concurrency)
                    """
                )
                #expect(
                    snapshot.prefetchBlocks >= snapshot.concurrency,
                    """
                    depth below concurrency at B=\(bandwidth) L=\(latency): \
                    depth=\(snapshot.prefetchBlocks) concurrency=\(snapshot.concurrency)
                    """
                )
            }
        }
    }
}
#endif
