import Foundation
import PlaybackCore
import Testing

@testable import Playback

@MainActor
struct PlaybackMediaSessionDriverTests {
    @Test("a driver cannot represent a session detached from its controller")
    func failedOpenLeavesNoDetachedSession() async {
        let controller = PlaybackCoreController()
        let driver = PlaybackMediaSessionDriver(controller: controller)
        let missingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        await #expect(throws: Error.self) {
            try await driver.open(.init(url: missingURL))
        }

        #expect(controller.activeSession == nil)
        #expect(driver.sessionID == nil)
        #expect(driver.debugSnapshot() == nil)
    }

    @Test("callback unbinding and repeated close converge safely")
    func repeatedCloseUnbindsCallbacksOnce() async {
        let controller = PlaybackCoreController()
        let driver = PlaybackMediaSessionDriver(controller: controller)
        var observedStatuses: [PlaybackStatus] = []
        var observedContinuity: [PlaybackDeliveryContinuityPhase] = []
        driver.bindCallbacks(
            .init(
                onStatusChange: { observedStatuses.append($0) },
                onDeliveryContinuityChange: { observedContinuity.append($0.phase) }
            )
        )
        controller.onStatusChange?(.loading)
        controller.onDeliveryContinuityChange?(.init(phase: .inactive))

        await driver.close()
        let statusCountAfterFirstClose = observedStatuses.count
        await driver.close()

        #expect(statusCountAfterFirstClose >= 1)
        #expect(observedStatuses.count == statusCountAfterFirstClose)
        #expect(observedContinuity == [.inactive])
        #expect(controller.onStatusChange == nil)
        #expect(controller.onDiagnosticsChange == nil)
        #expect(controller.onDeliveryContinuityChange == nil)
        #expect(controller.onAcceptedVideoFormatRevisionChange == nil)
        #expect(controller.onSessionChange == nil)
        #expect(controller.onSubtitleCuesChange == nil)
        #expect(controller.onSubtitleFrameChange == nil)
        #expect(controller.onAudioSpectrumFrameChange == nil)
    }

    @Test("PlaybackRuntime delegates driver callbacks without changing visible state")
    func runtimeDelegatesDriverCallbacks() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(controller: controller)
        let url = URL(fileURLWithPath: "/tmp/driver-delegation.mp4")
        let request = PlaybackLaunchRequest(
            source: try PlaybackAddress(localFileURL: url),
            displayName: "driver-delegation.mp4"
        )
        runtime.prepareForPlayback(request)
        var diagnostics = PlaybackDiagnostics()
        diagnostics.currentSeconds = 12
        diagnostics.durationSeconds = 30
        var observations: [PlaybackRuntimeObservation] = []
        runtime.onPlaybackObservation = { observations.append($0) }

        controller.onStatusChange?(.playing)
        controller.onDiagnosticsChange?(diagnostics)
        controller.onAcceptedVideoFormatRevisionChange?(4)
        let output = runtime.outputObservation()

        #expect(runtime.lifecycle == .playing)
        #expect(runtime.productLifecycle == .playing)
        #expect(runtime.playbackPosition.seconds == 12)
        #expect(runtime.playbackPosition.duration == 30)
        #expect(runtime.effectiveVideoFormatRevision == 4)
        #expect(output.lifecycle == .playing)
        #expect(output.positionSeconds == 12)
        #expect(
            observations.map(\.event)
                == [
                    .lifecycle(.playing),
                    .diagnostics(
                        position: .init(seconds: 12, duration: 30),
                        actualPlaybackSeconds: 0
                    )
                ]
        )

        await runtime.stopAndWait()
    }
}
