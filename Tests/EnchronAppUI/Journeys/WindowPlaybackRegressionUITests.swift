import XCTest

nonisolated final class WindowPlaybackRegressionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
#if targetEnvironment(simulator)
        throw XCTSkip("Window playback regression requires a physical Apple Vision Pro.")
#endif
    }

    @MainActor
    func testConfiguredMediaDisplaysFirstFrame() throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredWindowMedia(identifier: identifier) else { return }
        let stateElement = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard let displayed = waitForState(stateElement, timeout: 60, where: {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && ($0.uint64("rendererInputs") ?? 0) > 0
        }) else { return }
        XCTAssertEqual(displayed.string("loadingSpinner"), "off")
        attachState(displayed, name: "configured-media-first-frame-state")
        attachScreenshot(from: app, name: "configured-media-first-frame")
    }

    @MainActor
    func testLocalMediaWindowPlaybackLifecycle() throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredWindowMedia(identifier: identifier) else { return }

        let stateElement = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard let startup = waitForState(stateElement, timeout: 60, where: {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("attached") == "window"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.bool("displayedPixel") == true
                && ($0.uint64("videoSamples") ?? 0) > 0
                && ($0.uint64("rendererInputs") ?? 0) > 0
        }) else { return }
        attachState(startup, name: "window-playback-01-startup")
        attachScreenshot(from: app, name: "window-playback-01-startup")

        guard let startupContinuous = requireContinuousPlayback(
            after: startup,
            in: stateElement,
            app: app,
            name: "window-playback-02-startup-continuous"
        ) else { return }
        assertMechanicalAudioOutputAdvanced(
            from: startup,
            to: startupContinuous,
            context: "Window startup"
        )

        let play = app.buttons["PlayerPanel-button-play"].firstMatch
        guard requireHittable(play, named: "Pause") else { return }
        play.tap()
        guard let paused = waitForState(stateElement, timeout: 10, where: {
            $0.string("lifecycle")?.lowercased() == "paused"
                && abs($0.double("actualRate") ?? 1) < 0.01
        }) else { return }
        attachState(paused, name: "window-playback-03-paused")
        attachScreenshot(from: app, name: "window-playback-03-paused")

        play.tap()
        guard let resumed = waitForState(stateElement, timeout: 10, where: {
            $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0
                && $0.string("session") == startup.string("session")
        }) else { return }
        guard let resumedContinuous = requireContinuousPlayback(
            after: resumed,
            in: stateElement,
            app: app,
            name: "window-playback-04-resumed"
        ) else { return }

        let forward = app.buttons["PlayerPanel-button-forward"].firstMatch
        guard requireHittable(forward, named: "Forward 15 seconds") else { return }
        forward.tap()
        guard let seeked = waitForState(stateElement, timeout: 15, where: {
            ($0.uint64("streamEpoch") ?? 0)
                > (resumedContinuous.uint64("streamEpoch") ?? 0)
                && $0.string("session") == startup.string("session")
                && $0.string("lifecycle")?.lowercased() == "playing"
        }) else { return }
        guard requireContinuousPlayback(
            after: seeked,
            in: stateElement,
            app: app,
            name: "window-playback-05-playing-seek"
        ) != nil else { return }

        guard let position = seeked.double("position"),
              let duration = seeked.double("duration"),
              duration > 0 else { return }
        let forwardPressCount = Int(ceil(max(duration - position, 0) / 15))
        var endEpoch = seeked.uint64("streamEpoch") ?? 0
        for _ in 0..<forwardPressCount {
            guard requireHittable(forward, named: "Forward 15 seconds") else { return }
            forward.tap()
            guard let advanced = waitForState(stateElement, timeout: 15, where: {
                ($0.uint64("streamEpoch") ?? 0) > endEpoch
                    && $0.string("lifecycle")?.lowercased() != "failed"
            }) else { return }
            endEpoch = advanced.uint64("streamEpoch") ?? endEpoch
        }
        guard let ended = waitForState(stateElement, timeout: 15, where: { snapshot in
            guard let position = snapshot.double("position"),
                  let duration = snapshot.double("duration") else { return false }
            return snapshot.string("lifecycle")?.lowercased() == "ended"
                || position >= duration - 0.25
        }) else { return }
        attachState(ended, name: "window-playback-07-end-boundary")
        attachScreenshot(from: app, name: "window-playback-07-end-boundary")
        XCTAssertNotEqual(ended.string("lifecycle")?.lowercased(), "failed")
        XCTAssertFalse(app.alerts["Failed to Load"].exists)

        guard requireHittable(play, named: "Replay") else { return }
        play.tap()
        guard let replayed = waitForState(stateElement, timeout: 15, where: {
            $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0
                && ($0.double("position") ?? .greatestFiniteMagnitude) < 3
                && $0.string("session") == startup.string("session")
        }) else { return }
        guard requireContinuousPlayback(
            after: replayed,
            in: stateElement,
            app: app,
            name: "window-playback-08-replay"
        ) != nil else { return }

        let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
        guard requireHittable(back, named: "Back to Media Library") else { return }
        back.tap()
        let filesScreen = app.descendants(matching: .any)[
            "FileBrowsing-FilesScreen"
        ].firstMatch
        XCTAssertTrue(filesScreen.waitForExistence(timeout: 20))
        XCTAssertTrue(
            stateElement.waitForNonExistence(timeout: 15),
            "Closing playback must remove the Window control plane."
        )
        attachScreenshot(from: app, name: "window-playback-09-returned-to-library")

        attachHumanReviewBoundary(
            "The state projection proves that audio samples reached an active system output route. "
                + "Actual sound, synchronization and wearer-perceived quality require calibrated acoustic or human evidence.",
            name: "window-playback-audio-human-boundary"
        )
    }
}
