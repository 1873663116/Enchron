#if DEBUG
import Foundation
import Testing

@testable import MediaSource

@Suite(.serialized)
struct PipelineRobustnessTests {
    @Test("cache eviction keeps memory under the configured cap")
    func cacheStaysUnderCap() async throws {
        let cap = 1_024 * 1_024
        let pipeline = MediaReadPipeline(
            configuration: MediaReadPipeline.Configuration(
                blockSize: 256 * 1_024,
                cacheCapacityBytes: cap
            ),
            contentLength: 64 * 1_024 * 1_024,
            backendRead: { range in
                MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        for index in 0..<16 {
            let start = Int64(index) * 256 * 1_024
            _ = try await pipeline.read(start..<(start + 256 * 1_024))
        }
        let snapshot = await pipeline.snapshot()
        #expect(snapshot.cachedBytes <= cap)
    }

    @Test("a changed content length invalidates cached blocks")
    func changedContentLengthInvalidatesCache() async throws {
        final class LengthSource: @unchecked Sendable {
            private let lock = NSLock()
            private var length: Int64 = 10
            private var calls = 0
            func set(_ next: Int64) {
                lock.withLock { length = next }
            }
            func current() -> Int64 {
                lock.withLock { length }
            }
            func recordCall() {
                lock.withLock { calls += 1 }
            }
            func callCount() -> Int {
                lock.withLock { calls }
            }
        }
        let source = LengthSource()
        let pipeline = MediaReadPipeline(
            configuration: MediaReadPipeline.Configuration(
                blockSize: 4,
                cacheCapacityBytes: 1_024
            ),
            contentLength: 10,
            backendRead: { range in
                source.recordCall()
                return MediaByteRangeRead(
                    data: Data(repeating: 7, count: Int(range.count)),
                    contentLength: source.current(),
                    supportsSeeking: true
                )
            }
        )
        _ = try await pipeline.read(0..<2)
        source.set(20)
        _ = try await pipeline.read(4..<6)
        let before = source.callCount()
        _ = try await pipeline.read(0..<2)
        #expect(source.callCount() > before)
    }

    @Test("cancelling in-flight prefetch releases the pipeline")
    func cancelReleasesInFlight() async throws {
        let pipeline = MediaReadPipeline(
            configuration: MediaReadPipeline.Configuration(
                blockSize: 256 * 1_024,
                cacheCapacityBytes: 4 * 1_024 * 1_024
            ),
            contentLength: 64 * 1_024 * 1_024,
            backendRead: { range in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return MediaByteRangeRead(
                    data: Data(count: Int(range.count)),
                    contentLength: nil,
                    supportsSeeking: true
                )
            }
        )
        let task = Task {
            try await pipeline.read(0..<(256 * 1_024))
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        await pipeline.cancelAll()
        _ = try? await task.value
        let snapshot = await pipeline.snapshot()
        #expect(snapshot.activeReads == 0)
    }
}
#endif
