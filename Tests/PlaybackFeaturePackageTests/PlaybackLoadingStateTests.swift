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

    @Test("delivery lag starvation is visible until the timeline changes")
    func deliveryLagStarvationClearsOnInactive() {
        var stateMachine = activeLoadingStateMachine()
        var starvation = deliveryContinuityObservation(.starved, incidentID: 9)
        starvation.evidence?.detectionSource = .deliveryLag
        starvation.evidence?.watchdogCause = nil

        stateMachine.receive(
            starvation,
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        #expect(stateMachine.state.visibility == .loading)
        #expect(stateMachine.state.stage == .starved)

        stateMachine.receive(
            PlaybackDeliveryContinuityObservation(phase: .inactive),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        #expect(stateMachine.state == .none)
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

    @Test("starvation observed during a seek stays invisible behind the seek")
    func starvationDuringASeekIsIgnoredWhileSeeking() {
        var stateMachine = activeLoadingStateMachine()
        stateMachine.beginSeek(
            targetSeconds: 999.9,
            technicalSessionID: "session",
            runtimeGeneration: 1
        )
        #expect(stateMachine.state.stage == .seeking)

        stateMachine.receive(
            deliveryContinuityObservation(.starved, incidentID: 30),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )

        #expect(stateMachine.state.stage == .seeking)
    }

    @Test("ending a seek cannot clear a starvation that began after it")
    func endingASeekDoesNotClearALaterStarvation() {
        var stateMachine = activeLoadingStateMachine()
        stateMachine.beginSeek(
            targetSeconds: 42,
            technicalSessionID: "session",
            runtimeGeneration: 1
        )
        stateMachine.endSeek(technicalSessionID: "session", runtimeGeneration: 1)
        #expect(stateMachine.state == .none)

        stateMachine.receive(
            deliveryContinuityObservation(.starved, incidentID: 31),
            technicalSessionID: "session",
            runtimeGeneration: 1,
            lifecycle: .playing
        )
        stateMachine.endSeek(technicalSessionID: "session", runtimeGeneration: 1)

        #expect(stateMachine.state.stage == .starved)
    }

    @Test("a seek in flight past the indication delay shows seeking everywhere")
    func aSeekLongerThanTheIndicationDelayShowsTheSeekingStageInEveryPresentation()
        async throws {
        let runtime = try await openedAudioRuntime()
        defer { Task { await runtime.leavePlaybackAndWait(reason: .backButton) } }
        let gate = HeldSeek()
        runtime.debugSetSeekGate { await gate.wait() }
        runtime.seekIndicationDelay = .milliseconds(50)

        runtime.seek(to: 0.1)
        try await Task.sleep(for: .milliseconds(250))

        #expect(runtime.loadingState.stage == .seeking)
        #expect(runtime.loadingState.visibility == .loading)
        #expect(seekingEvidence(runtime)?.targetSeconds == 0.1)
        for presentation in PlaybackPresentation.allCases where presentation.usesImmersiveSpace {
            #expect(
                ImmersivePlaybackStallIndicatorPlacement.isVisible(
                    loadingStage: runtime.loadingState.stage,
                    presentation: presentation,
                    transitionIsActive: false
                )
            )
        }

        gate.release()
        await waitUntilSeekSettles(runtime)
    }

    @Test("a seek that settles inside the indication delay shows nothing")
    func aSeekShorterThanTheIndicationDelayShowsNothing() async throws {
        let runtime = try await openedAudioRuntime()
        defer { Task { await runtime.leavePlaybackAndWait(reason: .backButton) } }
        let gate = HeldSeek()
        runtime.debugSetSeekGate { await gate.wait() }
        runtime.seekIndicationDelay = .milliseconds(400)

        runtime.seek(to: 0.1)
        var observedSeeking = false
        let deadline = ContinuousClock.now + .milliseconds(800)
        var released = false
        let releaseAt = ContinuousClock.now + .milliseconds(60)
        while ContinuousClock.now < deadline {
            if released == false, ContinuousClock.now >= releaseAt {
                released = true
                gate.release()
            }
            if runtime.loadingState.stage == .seeking { observedSeeking = true }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(observedSeeking == false)
        #expect(runtime.loadingState == .none)
        await waitUntilSeekSettles(runtime)
    }

    @Test("a seek that completes clears the seeking stage")
    func aCompletedSeekClearsTheSeekingStage() async throws {
        let runtime = try await openedAudioRuntime()
        defer { Task { await runtime.leavePlaybackAndWait(reason: .backButton) } }
        let gate = HeldSeek()
        runtime.debugSetSeekGate { await gate.wait() }
        runtime.seekIndicationDelay = .milliseconds(50)

        runtime.seek(to: 0.1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(runtime.loadingState.stage == .seeking)

        gate.release()
        await waitUntilSeekSettles(runtime)

        #expect(runtime.loadingState == .none)
        #expect(
            ImmersivePlaybackStallIndicatorPlacement.isVisible(
                loadingStage: runtime.loadingState.stage,
                presentation: .docked,
                transitionIsActive: false
            ) == false
        )
    }

    @Test("a superseding seek restarts the indication delay")
    func aSupersedingSeekRestartsTheIndicationDelay() async throws {
        let runtime = try await openedAudioRuntime()
        defer { Task { await runtime.leavePlaybackAndWait(reason: .backButton) } }
        let gate = HeldSeek()
        runtime.debugSetSeekGate { await gate.wait() }
        runtime.seekIndicationDelay = .milliseconds(300)

        runtime.seek(to: 0.1)
        try await Task.sleep(for: .milliseconds(200))
        #expect(runtime.loadingState.stage != .seeking)

        runtime.seek(to: 0.2)
        try await Task.sleep(for: .milliseconds(200))
        #expect(runtime.loadingState.stage != .seeking)

        try await Task.sleep(for: .milliseconds(250))
        #expect(runtime.loadingState.stage == .seeking)
        #expect(seekingEvidence(runtime)?.targetSeconds == 0.2)

        gate.release()
        await waitUntilSeekSettles(runtime)
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

        await runtime.leavePlaybackAndWait(reason: .backButton)
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

@MainActor
private final class HeldSeek {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let pending = waiters
        waiters = []
        for continuation in pending {
            continuation.resume()
        }
    }
}

@MainActor
private func seekingEvidence(_ runtime: PlaybackRuntime) -> PlaybackSeekingEvidence? {
    guard case .seeking(let evidence) = runtime.loadingState.causalEvidence else {
        return nil
    }
    return evidence
}

@MainActor
private func waitUntilSeekSettles(_ runtime: PlaybackRuntime) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while runtime.seekIsInProgress, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func openedAudioRuntime() async throws -> PlaybackRuntime {
    let runtime = PlaybackRuntime(controller: PlaybackCoreController())
    let request = PlaybackLaunchRequest(
        source: try PlaybackAddress(localFileURL: audioFixtureURL()),
        displayName: audioFixtureURL().lastPathComponent
    )
    runtime.prepareForPlayback(request)
    try await runtime.open(
        request,
        startTimeSeconds: 0,
        initialSpeed: .default,
        initialFormat: nil
    )
    return runtime
}

private func audioFixtureURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(
            path: "TestMedia/TestVectors/Enchron/CodecContainer/Audio/"
                + "he-aac-v1-apple-audio-toolbox.m4a"
        )
}
