import Foundation
import PlaybackCore
import Testing

@testable import Playback

@MainActor
@Suite struct PlaybackLoadingStateTests {
    @Test("opening remains visible until the matching presentation is usable")
    func openingClosesOnUsablePresentation() {
        var stateMachine = PlaybackLoadingStateMachine()
        stateMachine.beginOpening(runtimeGeneration: 1, requestID: "request")
        stateMachine.bindTechnicalSession("session", runtimeGeneration: 1)

        #expect(stateMachine.state.visibility == .loading)
        #expect(stateMachine.state.stage == .opening)

        stateMachine.presentationBecameUsable(
            technicalSessionID: "session",
            runtimeGeneration: 1
        )

        #expect(stateMachine.state == .none)
    }

    @Test("only playing delivery starvation becomes visible")
    func trueStarvationRequiresPlayingLifecycle() {
        var stateMachine = activeLoadingStateMachine()
        let starvation = deliveryContinuityObservation(.starved, incidentID: 7)

        stateMachine.receive(
            starvation,
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .paused
        )
        #expect(stateMachine.state == .none)

        stateMachine.receive(
            starvation,
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        #expect(stateMachine.state.visibility == .loading)
        #expect(stateMachine.state.stage == .starved)
    }

    @Test("buffered reconnect and unmatched recovery remain invisible")
    func bufferedReconnectRemainsInvisible() {
        var stateMachine = activeLoadingStateMachine()

        stateMachine.receive(
            deliveryContinuityObservation(.recovered, incidentID: 4),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )

        #expect(stateMachine.state == .none)
    }

    @Test("matching recovery clears starvation only for the same incident")
    func recoveryMatchesStarvationIncident() {
        var stateMachine = activeLoadingStateMachine()
        stateMachine.receive(
            deliveryContinuityObservation(.starved, incidentID: 8),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )

        stateMachine.receive(
            deliveryContinuityObservation(.recovered, incidentID: 7),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        #expect(stateMachine.state.stage == .starved)

        stateMachine.receive(
            deliveryContinuityObservation(.recovered, incidentID: 8),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        #expect(stateMachine.state == .none)
    }

    @Test("pause clears starvation without creating opening")
    func pauseClearsStarvation() {
        var stateMachine = activeLoadingStateMachine()
        stateMachine.receive(
            deliveryContinuityObservation(.starved, incidentID: 9),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )

        stateMachine.clearStarvation()

        #expect(stateMachine.state == .none)
    }

    @Test("replacement opening rejects callbacks from the retired session")
    func replacementRejectsRetiredSessionCallbacks() {
        var stateMachine = activeLoadingStateMachine()
        stateMachine.beginOpening(
            runtimeGeneration: 1,
            requestID: "request",
            technicalSessionID: "replacement"
        )

        stateMachine.receive(
            deliveryContinuityObservation(.starved, incidentID: 10),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        #expect(stateMachine.state.stage == .opening)

        stateMachine.presentationBecameUsable(
            technicalSessionID: "replacement",
            runtimeGeneration: 1
        )
        #expect(stateMachine.state == .none)
    }

    @Test("callbacks from stale runtime generations cannot alter loading")
    func staleGenerationIsRejected() {
        var stateMachine = activeLoadingStateMachine()

        stateMachine.receive(
            deliveryContinuityObservation(.starved, incidentID: 11),
            technicalSessionID: "session",
            runtimeGeneration: 0,
            lifecycle: .playing
        )

        #expect(stateMachine.state == .none)
    }

    @Test("runtime integrates opening, continuity, recovery, pause, and stale callbacks")
    func runtimeIntegration() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: controller)
        let mediaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(
                path: "TestMedia/TestVectors/Enchron/CodecContainer/Audio/"
                    + "he-aac-v1-apple-audio-toolbox.m4a"
            )
        try #require(FileManager.default.fileExists(atPath: mediaURL.path))
        let request = PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: mediaURL),
            displayName: mediaURL.lastPathComponent
        )

        runtime.prepareForPlayback(request)
        #expect(runtime.loadingState.stage == .opening)
        try await runtime.open(
            request,
            startTimeSeconds: 0,
            initialSpeed: .default,
            initialFormat: nil
        )
        #expect(runtime.loadingState == .none)

        controller.onDeliveryContinuityChange?(
            deliveryContinuityObservation(.recovered, incidentID: 20)
        )
        #expect(runtime.loadingState == .none)

        controller.onStatusChange?(.playing)
        controller.onDeliveryContinuityChange?(
            deliveryContinuityObservation(.starved, incidentID: 21)
        )
        #expect(runtime.loadingState.stage == .starved)

        controller.onDeliveryContinuityChange?(
            deliveryContinuityObservation(.recovered, incidentID: 21)
        )
        #expect(runtime.loadingState == .none)

        controller.onDeliveryContinuityChange?(
            deliveryContinuityObservation(.starved, incidentID: 22)
        )
        controller.onStatusChange?(.paused)
        #expect(runtime.loadingState == .none)

        runtime.prepareForPlayback(request)
        controller.onDeliveryContinuityChange?(
            deliveryContinuityObservation(.starved, incidentID: 23)
        )
        #expect(runtime.loadingState.stage == .opening)

        await runtime.stopAndWait()
    }
}

@MainActor
private func activeLoadingStateMachine() -> PlaybackLoadingStateMachine {
    var stateMachine = PlaybackLoadingStateMachine()
    stateMachine.beginOpening(runtimeGeneration: 1, requestID: "request")
    stateMachine.bindTechnicalSession("session", runtimeGeneration: 1)
    stateMachine.presentationBecameUsable(
        technicalSessionID: "session",
        runtimeGeneration: 1
    )
    return stateMachine
}

@MainActor
private func deliveryContinuityObservation(
    _ phase: PlaybackDeliveryContinuityPhase,
    incidentID: UInt64
) -> PlaybackDeliveryContinuityObservation {
    PlaybackDeliveryContinuityObservation(
        phase: phase,
        evidence: PlaybackDeliveryContinuityEvidence(
            incidentID: incidentID,
            detectionSource: .hostWatchdog,
            watchdogCause: .frozenMediaClock,
            requiredLanes: ["audio", "video"],
            rateApplicationGeneration: 1,
            videoStreamEpoch: 1,
            audioStreamEpoch: 1,
            requestedRate: 1,
            frozenMediaTimeSeconds: 5,
            exhaustedPresentationEndSeconds: ["audio": 5, "video": 5],
            recoveredMediaTimeSeconds: phase == .recovered ? 6 : nil,
            recoveredPresentationEndSeconds: phase == .recovered
                ? ["audio": 8, "video": 8]
                : nil
        )
    )
}
