import PlaybackCore
import PlaybackPresentation
import XCTest
@testable import Enchron

#if DEBUG
nonisolated final class PlaybackSwitchStateRingTests: XCTestCase {
    func testCapacityRetainsEveryRecordThroughItsBoundary() {
        let ring = PlaybackSwitchStateRing(capacity: 3)
        _ = ring.arm(context: context())

        ring.record(rendererSample(at: 10))
        ring.record(rendererSample(at: 20))
        ring.record(rendererSample(at: 30))

        let snapshot = ring.snapshot()
        XCTAssertEqual(snapshot.records.map(\.monotonicNanoseconds), [10, 20, 30])
        XCTAssertEqual(snapshot.overwrittenRecordCount, 0)
    }

    func testFullRingOverwritesTheOldestRecordInChronologicalOrder() {
        let ring = PlaybackSwitchStateRing(capacity: 3)
        _ = ring.arm(context: context())

        ring.record(rendererSample(at: 10))
        ring.record(rendererSample(at: 20))
        ring.record(rendererSample(at: 30))
        ring.record(rendererSample(at: 40))

        let snapshot = ring.snapshot()
        XCTAssertEqual(snapshot.records.map(\.monotonicNanoseconds), [20, 30, 40])
        XCTAssertEqual(snapshot.overwrittenRecordCount, 1)
    }

    func testArmAndDisarmFenceGenerationsAndRearmClearsTheCapture() {
        let ring = PlaybackSwitchStateRing(capacity: 4)
        let firstGeneration = ring.arm(context: context())
        ring.record(rendererSample(at: 10))

        XCTAssertFalse(ring.disarm(generation: firstGeneration + 1))
        ring.record(rendererSample(at: 20))
        XCTAssertTrue(ring.disarm(generation: firstGeneration))
        ring.record(rendererSample(at: 30))
        XCTAssertEqual(ring.snapshot().records.map(\.monotonicNanoseconds), [10, 20])

        let secondGeneration = ring.arm(context: context(settled: .portal))
        XCTAssertGreaterThan(secondGeneration, firstGeneration)
        XCTAssertTrue(ring.snapshot().records.isEmpty)
        XCTAssertTrue(ring.snapshot().isArmed)
    }

    func testPresentationChangeToFirstNewGraphDisplayProgressUsesMonotonicTime() throws {
        let metrics = try XCTUnwrap(capturedSwitchMetrics())
        XCTAssertEqual(metrics.switchDurationNanoseconds, 40)
    }

    func testLongestDisplayProgressStallUsesOnlyConservativeDisplayProgress() throws {
        let metrics = try XCTUnwrap(capturedSwitchMetrics())
        XCTAssertEqual(metrics.longestDisplayProgressStallNanoseconds, 30)
    }

    func testTimebaseRateZeroDurationIsDerivedAcrossRendererSamples() throws {
        let metrics = try XCTUnwrap(capturedSwitchMetrics())
        XCTAssertTrue(metrics.timebaseRateReachedZero)
        XCTAssertEqual(metrics.timebaseRateZeroDurationNanoseconds, 20)
    }

    func testGraphChangesAndByteStreamDeltasSurviveTechnicalSessionRevisionReset() throws {
        let metrics = try XCTUnwrap(capturedSwitchMetrics())
        XCTAssertEqual(metrics.graphChangeCount, 1)
        XCTAssertEqual(metrics.byteStreamAcceptedConnectionDelta, 1)
        XCTAssertEqual(metrics.byteStreamRequestDelta, 2)
    }

    private func capturedSwitchMetrics() -> PlaybackSwitchDerivedMetrics? {
        let ring = PlaybackSwitchStateRing(capacity: 16)
        let generation = ring.arm(
            context: context(),
            byteStreamCounters: .init(
                scope: 7,
                acceptedConnectionCount: 3,
                requestCount: 8
            )
        )
        ring.record(rendererSample(at: 0, displayed: 10))
        _ = ring.beginSwitch(
            kind: .presentation,
            targetPresentation: .portal,
            at: 10
        )
        ring.record(rendererSample(at: 20, displayed: 11))
        ring.record(rendererSample(
            at: 30,
            technicalSessionID: "technical-new",
            rendererIdentity: 200,
            graphRevision: 1,
            displayed: 0,
            actualRate: 0
        ))
        ring.updateByteStreamCounters(.init(
            scope: 7,
            acceptedConnectionCount: 4,
            requestCount: 10
        ))
        ring.record(rendererSample(
            at: 50,
            technicalSessionID: "technical-new",
            rendererIdentity: 200,
            graphRevision: 1,
            displayed: 1
        ))
        _ = ring.disarm(generation: generation)
        return PlaybackSwitchStateAnalysis.derive(from: ring.snapshot()).switches.first
    }

    private func context(
        settled: PlaybackPresentation = .window
    ) -> PlaybackSwitchTraceContext {
        PlaybackSwitchTraceContext(
            logicalSessionID: "logical-session",
            settledPresentation: settled,
            targetPresentation: nil
        )
    }

    private func rendererSample(
        at time: UInt64,
        technicalSessionID: String = "technical-old",
        rendererIdentity: UInt64 = 100,
        graphRevision: UInt64 = 9,
        displayed: UInt64 = 0,
        actualRate: Float = 1
    ) -> PlaybackSwitchRendererSample {
        PlaybackSwitchRendererSample(
            monotonicNanoseconds: time,
            trigger: .periodic,
            technicalSessionID: technicalSessionID,
            rendererIdentity: rendererIdentity,
            graphRevision: graphRevision,
            lifecycle: .playing,
            acceptedInputCount: time,
            displayedFrameObservationCount: displayed,
            requestedRate: 1,
            actualTimebaseRate: actualRate,
            effectiveTimebaseRate: actualRate,
            streamEpoch: 1,
            flushCount: 0
        )
    }
}
#endif
