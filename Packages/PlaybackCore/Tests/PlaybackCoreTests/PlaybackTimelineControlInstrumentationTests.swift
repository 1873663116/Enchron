@testable import PlaybackCore
import Testing

@Suite struct PlaybackTimelineControlInstrumentationTests {
    @Test func activationReturnAndLaterStopRemainOrderedAcrossRefresh() throws {
        let store = PlaybackDiagnosticsStore()
        let activationSequence = store.beginTimelineRateActivation(
            reason: .decoderBootstrap,
            mediaTimeSeconds: 12.5,
            hostTimeSeconds: 100.25,
            currentVideoDeliveryGeneration: 4,
            capturedVideoDeliveryGeneration: 4,
            currentState: PlaybackTimelineControlStateRecord(
                isPrerolling: true,
                hasStartedTimeline: true,
                timelineStartRate: 1,
                requestedTimelineStartSeconds: 12.5
            )
        )

        let activationBeforeReturn = try #require(
            store.snapshot().timelineControlState?.lastRateActivation
        )
        #expect(activationBeforeReturn.sequence == activationSequence)
        #expect(activationBeforeReturn.synchronousApplicationReturned == false)

        store.recordTimelineRateActivationReturned(sequence: activationSequence)

        let activationAfterReturn = try #require(
            store.snapshot().timelineControlState?.lastRateActivation
        )
        #expect(activationAfterReturn.sequence == activationSequence)
        #expect(activationAfterReturn.synchronousApplicationReturned)

        store.recordTimelineStop(
            reason: .pause,
            mediaTimeSeconds: 13,
            currentVideoDeliveryGeneration: 5,
            capturedVideoDeliveryGeneration: nil,
            currentState: PlaybackTimelineControlStateRecord(
                isPrerolling: false,
                hasStartedTimeline: true,
                timelineStartRate: 0,
                requestedTimelineStartSeconds: 12.5
            )
        )
        store.recordTimelineControlState(PlaybackTimelineControlStateRecord(
            isPrerolling: false,
            hasStartedTimeline: true,
            timelineStartRate: 0,
            requestedTimelineStartSeconds: 13
        ))

        let finalState = try #require(store.snapshot().timelineControlState)
        let preservedActivation = try #require(finalState.lastRateActivation)
        let laterStop = try #require(finalState.lastStop)
        #expect(preservedActivation == activationAfterReturn)
        #expect(laterStop.sequence > preservedActivation.sequence)
        #expect(finalState.requestedTimelineStartSeconds == 13)
    }
}
