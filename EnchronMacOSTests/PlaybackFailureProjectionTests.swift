import PlaybackCore
import XCTest
@testable import EnchronMacOS

nonisolated final class PlaybackFailureProjectionTests: XCTestCase {
    @MainActor
    func testPlayableCoreStatusRemovesTheFailureProjection() async throws {
        let controller = PlaybackCoreController()
        let runtime = PlaybackRuntime(
            controller: controller,
            isUITestFixture: true,
            audioSessionLifecycle: PlaybackAudioSessionLifecycle()
        )
        let receiveStatus = try XCTUnwrap(controller.onStatusChange)

        try await runtime.open(request(named: "Playable Video"))
        receiveStatus(.failed("A stale open error"))
        XCTAssertEqual(runtime.lastErrorMessage, "A stale open error")

        receiveStatus(.playing)

        XCTAssertEqual(runtime.lifecycle, .playing)
        XCTAssertNil(runtime.lastErrorMessage)
    }

    @MainActor
    func testSuccessfulSurfaceAttachRemovesAnEarlierAttachFailure() async throws {
        let runtime = PlaybackRuntime(isUITestFixture: true)
        try await runtime.open(request(named: "Attached Video"))
        runtime.lastErrorMessage = "The playback surface could not attach."

        try runtime.attach(
            entityID: "replacement-surface",
            realityViewID: "replacement-reality-view",
            presentation: .window
        )

        XCTAssertEqual(runtime.lifecycle, .playing)
        XCTAssertEqual(runtime.attachedPresentation, .window)
        XCTAssertNil(runtime.lastErrorMessage)
    }

    @MainActor
    func testFailureOverlayCloseAndRetryActionsTransitionPlaybackState() async throws {
        let runtime = PlaybackRuntime(isUITestFixture: true)
        let launcher = PlaybackLaunchCoordinator(playbackRuntime: runtime)
        let request = request(named: "Action Video")
        try await runtime.open(request)
        runtime.lastErrorMessage = "Retryable failure"

        runtime.lastErrorMessage = nil
        launcher.beginPlayback(request)
        await Task.yield()

        XCTAssertTrue(runtime.hasActivePlaybackRequest)
        XCTAssertNil(runtime.lastErrorMessage)

        launcher.stopPlayback()

        XCTAssertFalse(runtime.hasActivePlaybackRequest)
        XCTAssertNil(runtime.lastErrorMessage)
    }

    private func request(named name: String) -> PlaybackLaunchRequest {
        PlaybackLaunchRequest(
            url: URL(fileURLWithPath: "/tmp/\(name).mkv"),
            displayName: name
        )
    }
}
