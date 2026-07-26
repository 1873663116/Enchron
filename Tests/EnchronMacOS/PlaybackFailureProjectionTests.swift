import PlaybackCore
import PlaybackFeature
import XCTest
@testable import EnchronMacOS

nonisolated final class PlaybackFailureProjectionTests: XCTestCase {
    @MainActor
    func testPlayableCoreStatusRemovesTheFailureProjection() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(
            controller: controller,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
        let receiveStatus = try XCTUnwrap(controller.onStatusChange)

        receiveStatus(.failed("A stale open error"))
        XCTAssertEqual(runtime.lastErrorMessage, "A stale open error")

        receiveStatus(.playing)

        XCTAssertEqual(runtime.lifecycle, .playing)
        XCTAssertNil(runtime.lastErrorMessage)
    }

    @MainActor
    func testLateTimelineControlFailureDoesNotRecreateFailureAfterPlaybackIsUsable() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(
            controller: controller,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
        let receiveStatus = try XCTUnwrap(controller.onStatusChange)

        receiveStatus(.playing)
        runtime.fail(PlaybackControlError.timelineNotReady)

        XCTAssertEqual(runtime.lifecycle, .playing)
        XCTAssertNil(runtime.lastErrorMessage)

        runtime.fail(PlaybackControlError.invalidRate(-1))
        XCTAssertEqual(
            runtime.lastErrorMessage,
            "The requested playback rate -1.0 is invalid."
        )

        receiveStatus(.failed("The renderer stopped accepting samples."))
        XCTAssertEqual(
            runtime.lifecycle,
            .failed("The renderer stopped accepting samples.")
        )
        XCTAssertEqual(runtime.lastErrorMessage, "The renderer stopped accepting samples.")
    }

    @MainActor
    func testWaitingForStopAfterOpenFailureClosesPlaybackCoreAndClearsProjection() async throws {
        let runtime = PlaybackRuntime()
        let launcher = PlaybackLaunchCoordinator(playbackRuntime: runtime)
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: "missing-\(UUID().uuidString).mkv")

        launcher.beginPlayback(.init(url: missingURL, displayName: "Missing Video"))

        let deadline = ContinuousClock.now + .seconds(5)
        while runtime.lastErrorMessage == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        guard case .failed = runtime.lifecycle else {
            return XCTFail("Expected PlaybackCore to publish failed, got \(runtime.lifecycle)")
        }
        XCTAssertTrue(runtime.hasActivePlaybackRequest)

        await launcher.stopPlaybackAndWait()

        XCTAssertEqual(runtime.lifecycle, .idle)
        XCTAssertFalse(runtime.hasActivePlaybackRequest)
        XCTAssertNil(runtime.currentLaunchRequest)
        XCTAssertNil(runtime.activeSessionID)
        XCTAssertNil(runtime.renderer)
        XCTAssertNil(runtime.attachedPresentation)
        XCTAssertNil(runtime.rendererConsumerPresentation)
        XCTAssertNil(runtime.rendererConsumerEntityID)
    }
}
