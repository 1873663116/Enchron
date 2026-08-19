import Foundation
import XCTest

nonisolated final class SpatialHandoffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Spatial handoff regression requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testWindowPlaybackInputOwnership() throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredSpatialMedia(identifier: identifier) else { return }

        XCTAssertFalse(
            app.descendants(matching: .any)["PlayerUI-spatial-state"].firstMatch.exists,
            "This Window-only regression must not enter an Immersive Space."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch.exists,
            "The registered diagnostic media must begin in Window presentation."
        )

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let initial = try XCTUnwrap(waitForState(windowState, timeout: 45) {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("attached") == "window"
                && $0.string("controls") == "shown"
                && $0.string("chrome") == "on"
                && $0.bool("videoVisible") == true
                && $0.string("lifecycle")?.lowercased() == "playing"
        })
        attachState(initial, name: "window-input-01-initial-shown")
        attachScreenshot(from: app, name: "window-input-01-initial-shown")
        let initialProjection = try XCTUnwrap(initial.string("projection"))
        let initialStereoLayout = try XCTUnwrap(initial.string("stereoLayout"))
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "window-input-current-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "initial Window controls"
        )

        let playbackSurface = app.buttons[
            "PlayerUI-window-playback-surface"
        ].firstMatch
        guard requireHittable(
            playbackSurface,
            named: "Window playback surface"
        ) else { return }
        playbackSurface.tap()
        let hidden = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("controls") == "hidden"
                && $0.string("chrome") == "off"
                && $0.string("tapTrace") == "toggled:hidden"
        })
        attachState(hidden, name: "window-input-02-hidden")
        attachScreenshot(from: app, name: "window-input-02-hidden")
        assertControlsVisibility(
            "hidden",
            remainsStableFor: 0.8,
            in: windowState,
            context: "one Window surface tap"
        )

        guard requireHittable(
            playbackSurface,
            named: "Window playback surface with controls hidden"
        ) else { return }
        playbackSurface.tap()
        let shownAgain = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("controls") == "shown"
                && $0.string("chrome") == "on"
                && $0.string("tapTrace") == "toggled:shown"
        })
        attachState(shownAgain, name: "window-input-03-shown-again")
        attachScreenshot(from: app, name: "window-input-03-shown-again")
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "second Window surface tap"
        )

        let playPause = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(playPause, named: "Window Play/Pause") else { return }
        XCTAssertEqual(playPause.label, "Pause")
        playPause.tap()
        let paused = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("lifecycle")?.lowercased() == "paused"
                && ($0.double("actualRate") ?? 1) == 0
                && $0.string("controls") == "shown"
        })
        attachState(paused, name: "window-input-03a-paused")
        XCTAssertEqual(playPause.label, "Play")
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "Pause action"
        )

        let format = app.descendants(matching: .any)[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        guard requireHittable(format, named: "Window Video Format") else { return }
        format.tap()
        let cancelFormat = app.buttons["PlayerUI-VideoFormat-cancel"].firstMatch
        guard requireHittable(cancelFormat, named: "Cancel Video Format") else { return }
        _ = try XCTUnwrap(waitForState(windowState, timeout: 5) {
            $0.string("controls") == "shown"
        })
        attachScreenshot(from: app, name: "window-input-04a-video-format-open")
        format.tap()
        XCTAssertTrue(
            cancelFormat.waitForNonExistence(timeout: 5),
            "Video Format panel remained visible after tapping its top action again."
        )
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "closing Video Format with its top action"
        )
        guard requireHittable(
            format,
            named: "Window Video Format after closing its panel"
        ) else { return }
        format.tap()
        guard requireHittable(
            cancelFormat,
            named: "Cancel reopened Video Format"
        ) else { return }

        let panorama360 = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-360°"
        ].firstMatch
        guard requireHittable(panorama360, named: "360° Video Format") else { return }
        panorama360.tap()
        let sideBySide = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Stereo Layout-Side-by-Side"
        ].firstMatch
        guard requireHittable(sideBySide, named: "Side-by-Side Video Format") else { return }
        sideBySide.tap()
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "Video Format action"
        )
        attachScreenshot(from: app, name: "window-input-04-video-format")
        cancelFormat.tap()
        let cancelledFormat = try XCTUnwrap(waitForState(windowState, timeout: 5) {
            $0.string("projection") == initialProjection
                && $0.string("stereoLayout") == initialStereoLayout
                && $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("controls") == "shown"
        })
        attachState(cancelledFormat, name: "window-input-05-video-format-cancelled")
        XCTAssertTrue(
            cancelFormat.waitForNonExistence(timeout: 5),
            "Video Format state closed but its accessibility element remained visible."
        )
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "closing Video Format"
        )

        let dock = app.descendants(matching: .any)[
            "PlayerUI-TopAction-dock"
        ].firstMatch
        guard requireHittable(dock, named: "Window Dock") else { return }
        dock.tap()
        let dockMenu = app.descendants(matching: .any)[
            "PlayerUI-DockMenu"
        ].firstMatch
        XCTAssertTrue(dockMenu.waitForExistence(timeout: 5))
        attachScreenshot(from: app, name: "window-input-05a-dock-menu")
        dock.tap()
        XCTAssertTrue(dockMenu.waitForNonExistence(timeout: 5))

        let more = app.descendants(matching: .any)[
            "PlayerUI-TopAction-more"
        ].firstMatch
        guard requireHittable(more, named: "Window More") else { return }
        more.tap()
        let subtitlesMenu = app.buttons["PlayerUI-menu-subtitles"].firstMatch
        guard requireHittable(
            subtitlesMenu,
            named: "Subtitles in system More menu"
        ) else { return }
        attachScreenshot(from: app, name: "window-input-06-more")

        subtitlesMenu.tap()
        let subtitlesOff = app.buttons["Off"].firstMatch
        guard requireHittable(
            subtitlesOff,
            named: "Turn subtitles off"
        ) else { return }
        subtitlesOff.tap()
        XCTAssertTrue(
            windowState.waitForExistence(timeout: 5),
            "Window playback state did not return after choosing a system menu item."
        )
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "selecting a More menu item"
        )

        XCTAssertEqual(playPause.label, "Play")
        playPause.tap()
        let playingAgain = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0
                && $0.string("controls") == "shown"
        })
        XCTAssertEqual(playPause.label, "Pause")
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "Play action"
        )
        attachState(playingAgain, name: "window-input-08-playing-again")
        attachScreenshot(from: app, name: "window-input-08-playing-again")

        let progress = app.descendants(matching: .any)[
            "PlayerPanel-progress"
        ].firstMatch
        guard requireHittable(progress, named: "Playback progress") else { return }
        progress.doubleTap()
        let precisionTimeline = app.descendants(matching: .any)[
            "PlayerPanel-precision-timeline"
        ].firstMatch
        XCTAssertTrue(
            precisionTimeline.waitForExistence(timeout: 5),
            "Double activation must expand the Precision Timeline."
        )
        attachScreenshot(from: app, name: "window-input-09-timeline-expanded")

        Thread.sleep(forTimeInterval: 1.2)
        guard requireHittable(
            playbackSurface,
            named: "Window playback surface after closing menus"
        ) else { return }
        playbackSurface.tap()
        _ = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("controls") == "hidden"
                && $0.string("chrome") == "off"
                && $0.string("tapTrace") == "toggled:hidden"
        })
        XCTAssertTrue(
            precisionTimeline.waitForNonExistence(timeout: 5),
            "Hiding Player Controls must end the temporary Precision Timeline expansion."
        )
        attachScreenshot(from: app, name: "window-input-10-timeline-reset-hidden")

        guard requireHittable(
            playbackSurface,
            named: "Window playback surface after timeline reset"
        ) else { return }
        playbackSurface.tap()
        _ = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("controls") == "shown"
                && $0.string("chrome") == "on"
                && $0.string("tapTrace") == "toggled:shown"
        })
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertFalse(precisionTimeline.exists)
        attachScreenshot(from: app, name: "window-input-11-standard-progress-restored")
        attachHumanReviewBoundary(
            "Review the recording for duplicate surface reactions, control hit-through, and any visible layering conflict between the SwiftUI chrome and video surface.",
            name: "window-input-human-review-boundary"
        )
    }

    @MainActor
    private func assertControlsVisibility(
        _ expected: String,
        remainsStableFor duration: TimeInterval,
        in stateElement: XCUIElement,
        context: String
    ) {
        let deadline = Date().addingTimeInterval(duration)
        var observations: [String] = []
        repeat {
            let snapshot = RegressionStateSnapshot(
                rawValue: stateElement.value as? String ?? ""
            )
            let observed = snapshot.string("controls") ?? "missing"
            observations.append(observed)
            XCTAssertEqual(
                observed,
                expected,
                "\(context) caused an unexpected controls visibility change. state=\(snapshot.rawValue)"
            )
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        let attachment = XCTAttachment(
            string: "duration=\(duration); expected=\(expected); observations=\(observations.joined(separator: ","))"
        )
        attachment.name = "\(context)-visibility-stability"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWindowAndDockedCompleteRoundTrip() async throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredSpatialMedia(identifier: identifier) else { return }
        guard restoreWindowPlaybackIfSpatialPresentationIsActive(in: app),
              restoreFlatWindowFormatIfNeeded(in: app) else { return }

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let playingWindow = try XCTUnwrap(waitForState(windowState, timeout: 45) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
        })
        let session = try XCTUnwrap(playingWindow.string("session"))
        let playbackEntity = try XCTUnwrap(playingWindow.string("playbackEntity"))
        let videoComponentRevision = try XCTUnwrap(
            playingWindow.uint64("videoComponentRevision")
        )
        let rendererGraphRevision = try XCTUnwrap(
            playingWindow.uint64("lastRendererInputGraphRevision")
        )
        attachState(playingWindow, name: "dock-return-01-window-playing")
        let windowPlayPause = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(
            windowPlayPause,
            named: "Window Play/Pause before Dock"
        ) else { return }

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let light = app.buttons["PlayerUI-DockMenu-light"].firstMatch
        guard requireHittable(light, named: "Dock with Light Mode") else { return }
        light.tap()

        let pausedAtTransitionStart = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("transition") == "docked"
                && $0.string("lifecycle")?.lowercased() == "paused"
                && abs($0.double("actualRate") ?? 1) < 0.001
        })
        attachState(
            pausedAtTransitionStart,
            name: "dock-return-02-paused-before-window-release"
        )

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let docked = try observeTransitionToSpatialPresentation(
            app: app,
            originalSurface: windowState,
            originalTransportControl: windowPlayPause,
            targetPresentation: "docked"
        )
        XCTAssertEqual(docked.string("lifecycle")?.lowercased(), "paused")
        XCTAssertLessThan(abs(docked.double("actualRate") ?? 1), 0.001)
        XCTAssertEqual(docked.string("session"), session)
        let dockedPlaybackEntity = try XCTUnwrap(docked.string("playbackEntity"))
        XCTAssertNotEqual(dockedPlaybackEntity, playbackEntity)
        XCTAssertEqual(
            docked.uint64("videoComponentRevision"),
            videoComponentRevision
        )
        XCTAssertEqual(
            docked.uint64("lastRendererInputGraphRevision"),
            rendererGraphRevision
        )
        XCTAssertEqual(docked.string("rendererConsumer"), "docked")
        XCTAssertEqual(docked.string("rendererConsumerEntity"), "present")
        XCTAssertEqual(docked.bool("surfaceRenderingReady"), true)
        XCTAssertEqual(docked.bool("surfaceAnchorMatched"), true)
        XCTAssertEqual(docked.string("surfaceParent"), "PlaybackSurfaceAnchor")
        XCTAssertTrue(windowState.waitForNonExistence(timeout: 15))
        attachState(docked, name: "dock-return-03-docked-paused")

        let deckPlayPause = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(deckPlayPause, named: "Docked Player Controls deck") else { return }

        try await Task.sleep(for: .seconds(1))
        let dockedAfterObservation = RegressionStateSnapshot(
            rawValue: spatialState.value as? String ?? ""
        )
        attachState(
            dockedAfterObservation,
            name: "dock-return-04-docked-still-paused"
        )
        assertPausedOutputDidNotAdvance(
            from: docked,
            to: dockedAfterObservation,
            context: "settled Docked presentation"
        )
        attachScreenshot(from: app, name: "dock-return-04-docked-still-paused")

        let dockedHierarchy = XCTAttachment(string: app.debugDescription)
        dockedHierarchy.name = "dock-return-docked-accessibility-hierarchy"
        dockedHierarchy.lifetime = .keepAlways
        add(dockedHierarchy)

        deckPlayPause.tap()
        guard let dockedPlaying = waitForState(spatialState, timeout: 12, where: {
            $0.string("presentation") == "docked"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
                && $0.string("session") == session
        }) else { return }
        guard let dockedContinuous = requireContinuousPlayback(
            after: dockedPlaying,
            in: spatialState,
            app: app,
            name: "dock-return-05-docked-explicit-play"
        ) else { return }
        assertMechanicalAudioOutputAdvanced(
            from: dockedPlaying,
            to: dockedContinuous,
            context: "Docked explicit Play"
        )

        let exitSpatial = app.buttons.matching(
            identifier: "PlayerPanel-button-exit-spatial"
        ).firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return }
        exitSpatial.tap()

        let returned = try XCTUnwrap(waitForState(windowState, timeout: 45) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "paused"
                && abs($0.double("actualRate") ?? 1) < 0.001
        })
        XCTAssertEqual(returned.string("session"), session)
        let returnedPlaybackEntity = try XCTUnwrap(returned.string("playbackEntity"))
        XCTAssertNotEqual(returnedPlaybackEntity, dockedPlaybackEntity)
        XCTAssertEqual(
            returned.uint64("videoComponentRevision"),
            videoComponentRevision
        )
        XCTAssertEqual(
            returned.uint64("lastRendererInputGraphRevision"),
            rendererGraphRevision
        )
        attachState(returned, name: "dock-return-06-window-returned-paused")
        attachScreenshot(from: app, name: "dock-return-06-window-returned-paused")

        try await Task.sleep(for: .seconds(1))
        let returnedAfterObservation = RegressionStateSnapshot(
            rawValue: windowState.value as? String ?? ""
        )
        attachState(
            returnedAfterObservation,
            name: "dock-return-07-window-still-paused"
        )
        assertPausedOutputDidNotAdvance(
            from: returned,
            to: returnedAfterObservation,
            context: "returned Window presentation"
        )

        let windowPlay = app.buttons.matching(
            identifier: "PlayerPanel-button-play"
        ).firstMatch
        guard requireHittable(windowPlay, named: "Window Play") else { return }
        windowPlay.tap()

        let resumed = try XCTUnwrap(waitForState(windowState, timeout: 12) {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
                && ($0.uint64("displayedFrameObservations") ?? 0) >= 2
                && $0.bool("displayedPixel") == true
                && $0.string("videoRendererStatus") == "ready"
                && $0.string("error") == "none"
        })
        XCTAssertEqual(resumed.string("session"), session)
        XCTAssertEqual(resumed.string("playbackEntity"), returnedPlaybackEntity)
        XCTAssertEqual(
            resumed.uint64("videoComponentRevision"),
            videoComponentRevision
        )
        XCTAssertEqual(
            resumed.uint64("lastRendererInputGraphRevision"),
            rendererGraphRevision
        )
        guard let continued = requireContinuousPlayback(
            after: resumed,
            in: windowState,
            app: app,
            name: "dock-return-08-window-explicit-play"
        ) else { return }
        assertMechanicalAudioOutputAdvanced(
            from: resumed,
            to: continued,
            context: "Window explicit Play after Docked"
        )
        attachHumanReviewBoundary(
            "Review the full recording for transient black frames, duplicated surfaces, abrupt visual faults, and actual audible continuity across the Window and Docked handoff.",
            name: "window-docked-human-review-boundary"
        )
    }

    private func assertPausedOutputDidNotAdvance(
        from first: RegressionStateSnapshot,
        to second: RegressionStateSnapshot,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            second.string("lifecycle")?.lowercased(),
            "paused",
            "\(context) did not remain paused.",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            abs(second.double("actualRate") ?? 1),
            0.001,
            "\(context) restarted the shared audio/video timebase.",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            abs((second.double("position") ?? 0) - (first.double("position") ?? 0)),
            0.05,
            "\(context) advanced media time while paused.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            second.uint64("displayedFrameObservations"),
            first.uint64("displayedFrameObservations"),
            "\(context) displayed a later frame while paused.",
            file: file,
            line: line
        )
        if first.bool("hasAudio") == true {
            XCTAssertEqual(
                second.string("audioRendererError"),
                "none",
                "\(context) reported an audio renderer failure.",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func testWindowAndPanoramaCompleteRoundTrip() async throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredSpatialMedia(identifier: identifier) else { return }
        guard restoreWindowPlaybackIfSpatialPresentationIsActive(in: app) else { return }
        guard restoreFlatWindowFormatIfNeeded(in: app) else { return }

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let before = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 45
        ) {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.string("attached") == "window"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("skyboxActive") == false
        })
        let session = try XCTUnwrap(before.string("session"))
        let technicalSession = try XCTUnwrap(before.string("technicalSession"))
        let playbackEntity = try XCTUnwrap(before.string("playbackEntity"))
        let videoComponentRevision = try XCTUnwrap(
            before.uint64("videoComponentRevision")
        )
        let rendererGraphRevision = try XCTUnwrap(
            before.uint64("lastRendererInputGraphRevision")
        )
        let formatRevision = try XCTUnwrap(
            before.uint64("lastRendererInputFormatRevision")
        )
        let initialProjection = try XCTUnwrap(before.string("projection"))
        let initialStereoLayout = try XCTUnwrap(before.string("stereoLayout"))
        let windowPlay = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(windowPlay, named: "Window Play/Pause") else { return }
        attachScreenshot(from: app, name: "panorama-handoff-01-window")

        let format = app.descendants(matching: .any)[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        guard requireHittable(format, named: "Video Format") else { return }
        format.tap()
        let panorama = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-360°"
        ].firstMatch
        guard requireHittable(panorama, named: "360 degree projection") else { return }
        panorama.tap()
        let formatMenu = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat"
        ].firstMatch
        XCTAssertTrue(
            formatMenu.waitForExistence(timeout: 5),
            "Video Format panel did not remain visible while editing."
        )
        let cancel = app.buttons["PlayerUI-VideoFormat-cancel"].firstMatch
        guard requireHittable(cancel, named: "Cancel video format") else { return }
        let draft = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && $0.string("session") == session
        })
        attachState(draft, name: "panorama-handoff-02-uncommitted-draft")
        attachScreenshot(from: app, name: "panorama-handoff-02-uncommitted-draft")
        cancel.tap()
        _ = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            $0.string("projection") == initialProjection
                && $0.string("stereoLayout") == initialStereoLayout
                && $0.string("presentation") == "window"
                && $0.string("lifecycle")?.lowercased() == "playing"
        })
        XCTAssertTrue(
            formatMenu.waitForNonExistence(timeout: 5),
            "Video Format panel remained visible after Cancel."
        )

        // This fixture is intentionally only 30 seconds long. Rewind after
        // proving Cancel semantics so the round trip tests active-session
        // replacement instead of racing the natural end of the media.
        let rewind = app.buttons[
            "PlayerPanel-button-rewind"
        ].firstMatch
        guard requireHittable(rewind, named: "Rewind before handoff") else {
            return
        }
        let beforeRewind = try XCTUnwrap(waitForState(windowState, timeout: 5) {
            $0.string("lifecycle")?.lowercased() == "playing"
        })
        rewind.tap()
        _ = try XCTUnwrap(waitForState(windowState, timeout: 8) {
            ($0.uint64("streamEpoch") ?? 0)
                > (beforeRewind.uint64("streamEpoch") ?? 0)
                && ($0.double("position") ?? .infinity)
                    < (beforeRewind.double("position") ?? 0)
                && $0.string("lifecycle")?.lowercased() == "playing"
        })

        guard requireHittable(format, named: "Video Format after Cancel") else { return }
        format.tap()
        guard requireHittable(panorama, named: "360 degree projection after Cancel") else {
            return
        }
        panorama.tap()
        let apply = app.buttons["PlayerUI-VideoFormat-apply"].firstMatch
        guard requireHittable(apply, named: "Apply video format") else {
            attachCurrentState(
                of: windowState,
                name: "panorama-format-selection-window-state-at-failure"
            )
            attachScreenshot(
                from: app,
                name: "panorama-format-selection-failure"
            )
            return
        }
        attachScreenshot(from: app, name: "panorama-handoff-format-open")
        apply.tap()

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let portal = try XCTUnwrap(waitForState(windowState, timeout: 30) {
            $0.string("presentation") == "portal"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("attached") == "portal"
                && $0.string("projection") == "equirectangular360"
                && $0.string("stereoLayout") == initialStereoLayout
                && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                    > formatRevision
                && $0.bool("videoVisible") == true
                && $0.string("immersiveSpaceResidency") == "closed"
        })
        XCTAssertFalse(spatialState.exists)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "PlayerPanel-button-exit-spatial"
            ].firstMatch.exists
        )
        let enterPanorama = app.descendants(matching: .any)[
            "PlayerUI-TopAction-resumePanorama"
        ].firstMatch
        guard requireHittable(enterPanorama, named: "Enter Panorama") else { return }
        let portalComponentRevision = try XCTUnwrap(
            portal.uint64("videoComponentRevision")
        )
        XCTAssertEqual(portalComponentRevision, videoComponentRevision + 1)
        enterPanorama.tap()
        guard requirePresentationRequest(
            in: app,
            windowState: windowState,
            targetPresentation: "panorama"
        ) else { return }

        let spatial = try observeTransitionToSpatialPresentation(
            app: app,
            originalSurface: windowState,
            originalTransportControl: windowPlay,
            targetPresentation: "panorama"
        )
        XCTAssertEqual(spatial.string("session"), session)
        XCTAssertNotEqual(spatial.string("technicalSession"), technicalSession)
        let panoramaPlaybackEntity = try XCTUnwrap(spatial.string("playbackEntity"))
        XCTAssertNotEqual(panoramaPlaybackEntity, playbackEntity)
        let panoramaComponentRevision = try XCTUnwrap(
            spatial.uint64("videoComponentRevision")
        )
        let panoramaRendererGraphRevision = try XCTUnwrap(
            spatial.uint64("lastRendererInputGraphRevision")
        )
        XCTAssertEqual(
            panoramaComponentRevision,
            portalComponentRevision + 1,
            "The Panorama conversion must install one fresh technical playback session."
        )
        XCTAssertEqual(panoramaRendererGraphRevision, rendererGraphRevision)
        XCTAssertEqual(
            spatial.uint64("boundVideoComponentRevision"),
            panoramaComponentRevision
        )
        XCTAssertEqual(
            spatial.uint64("rendererPixelVideoComponentRevision"),
            panoramaComponentRevision
        )
        XCTAssertEqual(spatial.string("attached"), "panorama")
        XCTAssertEqual(spatial.string("rendererConsumer"), "panorama")
        XCTAssertEqual(spatial.string("rendererConsumerEntity"), "present")
        XCTAssertEqual(spatial.string("environment"), "none")
        XCTAssertEqual(spatial.string("environmentEffect"), "none")
        XCTAssertEqual(spatial.string("panoramaReturnEnvironment"), "none")
        XCTAssertEqual(spatial.string("panoramaReturnEnvironmentEffect"), "none")
        XCTAssertEqual(spatial.string("environmentCardResidency"), "closed")
        XCTAssertEqual(spatial.bool("skyboxActive"), false)
        XCTAssertEqual(spatial.string("skyboxOpacity"), "none")
        XCTAssertEqual(spatial.bool("surfaceSettled"), true)
        XCTAssertEqual(spatial.bool("surfaceRenderingReady"), true)
        XCTAssertEqual(
            spatial.string("rendererProjectionKind")?.lowercased(),
            "equirectangular"
        )
        XCTAssertEqual(spatial.string("surfaceContentType"), "equirectangular")
        let panoramaPlaying = try XCTUnwrap(waitForState(spatialState, timeout: 12) {
            $0.string("presentation") == "panorama"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
        })
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertTrue(windowState.waitForNonExistence(timeout: 15))
        attachState(panoramaPlaying, name: "panorama-handoff-state")

        let panoramaPlay = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(panoramaPlay, named: "Panorama Play/Pause") else { return }
        guard let panoramaContinuous = requireContinuousPlayback(
            after: panoramaPlaying,
            in: spatialState,
            app: app,
            name: "panorama-handoff-03-explicit-play"
        ) else { return }
        assertMechanicalAudioOutputAdvanced(
            from: panoramaPlaying,
            to: panoramaContinuous,
            context: "Panorama explicit Play"
        )
        guard try requireGeneratedColorBarsAreWearerVisible(
            in: app,
            timeout: 5,
            attachmentName: "panorama-handoff-03-playing-visible-video"
        ) else { return }

        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Portal") else { return }
        exitSpatial.tap()
        try observeTransitionToMainWindow(
            app: app,
            windowSurface: windowState,
            sourcePresentation: "panorama",
            targetPresentation: "portal",
            expectedChrome: "off"
        )
        let restored = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30
        ) {
            $0.string("presentation") == "portal"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("attached") == "portal"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("panoramaReturnEnvironment") == "inactive"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("skyboxActive") == false
                && $0.bool("videoVisible") == true
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
                && $0.string("desiredImmersiveMode") == "portal"
                && $0.string("actualImmersiveMode") == "portal"
                && $0.string("desiredSpatialVideoMode") == "screen"
                && $0.string("actualSpatialVideoMode") == "screen"
        })
        XCTAssertEqual(restored.string("session"), session)
        XCTAssertNotEqual(
            restored.string("technicalSession"),
            spatial.string("technicalSession")
        )
        XCTAssertNotEqual(restored.string("playbackEntity"), panoramaPlaybackEntity)
        XCTAssertEqual(
            restored.uint64("videoComponentRevision"),
            panoramaComponentRevision + 1
        )
        XCTAssertEqual(
            restored.uint64("lastRendererInputGraphRevision"),
            panoramaRendererGraphRevision
        )
        XCTAssertEqual(restored.string("projection"), spatial.string("projection"))
        XCTAssertEqual(restored.string("stereoLayout"), spatial.string("stereoLayout"))
        attachState(restored, name: "panorama-none-environment-window-return-state")
        attachScreenshot(from: app, name: "panorama-none-environment-window-return")

        let windowTopOverlay = app.descendants(matching: .any)[
            "PlayerUI-window-top-overlay"
        ].firstMatch
        XCTAssertTrue(
            windowTopOverlay.waitForNonExistence(timeout: 5),
            "Portal Playback Mode must keep the Window Playback overlay hidden."
        )

        let portalSettings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        guard requireHittable(
            portalSettings,
            named: "Portal Playback Advanced Settings"
        ) else { return }
        portalSettings.tap()

        let windowFormat = app.descendants(matching: .any)[
            "PlayerPanel-Advanced-ReturnToMonoWindow"
        ].firstMatch
        guard requireHittable(
            windowFormat,
            named: "Window video format from Portal Playback"
        ) else { return }
        windowFormat.tap()
        try? await Task.sleep(for: .seconds(2))
        if spatialState.exists,
           let rawValue = spatialState.value as? String {
            attachState(
                RegressionStateSnapshot(rawValue: rawValue),
                name: "panorama-flat-replacement-pending-state"
            )
        }

        guard let windowFormatApplied = waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30,
            where: {
                $0.string("presentation") == "window"
                    && $0.string("attached") == "window"
                    && $0.string("projection") == "flat"
                    && $0.string("stereoLayout") == "mono"
                    && $0.bool("videoVisible") == true
                    && $0.string("chrome") == "on"
            }
        ) else {
            attachScreenshot(
                from: app,
                name: "panorama-flat-window-format-failure"
            )
            XCTFail("Flat Window format did not finish applying.")
            return
        }
        let windowComponentRevision = try XCTUnwrap(
            windowFormatApplied.uint64("videoComponentRevision")
        )
        let windowRendererGraphRevision = try XCTUnwrap(
            windowFormatApplied.uint64("lastRendererInputGraphRevision")
        )
        let windowPlaybackEntity = try XCTUnwrap(
            windowFormatApplied.string("playbackEntity")
        )
        XCTAssertNotEqual(windowPlaybackEntity, panoramaPlaybackEntity)
        XCTAssertEqual(windowComponentRevision, panoramaComponentRevision + 2)
        XCTAssertEqual(windowRendererGraphRevision, panoramaRendererGraphRevision)
        XCTAssertEqual(
            windowFormatApplied.uint64("boundVideoComponentRevision"),
            windowComponentRevision
        )
        XCTAssertEqual(
            windowFormatApplied.uint64("rendererPixelVideoComponentRevision"),
            windowComponentRevision
        )
        XCTAssertTrue(
            windowTopOverlay.waitForExistence(timeout: 5),
            "Window Playback Mode must show its Window controls after applying Window format."
        )

        guard requireHittable(windowPlay, named: "Window Play/Pause after Panorama") else {
            return
        }
        guard let windowPlaying = waitForState(windowState, timeout: 12, where: {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("lifecycle")?.lowercased() == "playing"
                && ($0.double("actualRate") ?? 0) > 0.5
                && $0.string("session") == session
        }) else { return }
        XCTAssertEqual(windowPlaying.string("playbackEntity"), windowPlaybackEntity)
        XCTAssertEqual(
            windowPlaying.uint64("videoComponentRevision"),
            windowComponentRevision
        )
        XCTAssertEqual(
            windowPlaying.uint64("lastRendererInputGraphRevision"),
            windowRendererGraphRevision
        )
        guard let windowContinuous = requireContinuousPlayback(
            after: windowPlaying,
            in: windowState,
            app: app,
            name: "panorama-handoff-04-window-explicit-play"
        ) else { return }
        assertMechanicalAudioOutputAdvanced(
            from: windowPlaying,
            to: windowContinuous,
            context: "Window explicit Play after Panorama"
        )
        attachHumanReviewBoundary(
            "Review the recording for Panorama projection direction, scale, field of view, transient black frames, duplicated surfaces, and actual audible continuity.",
            name: "window-panorama-human-review-boundary"
        )
    }

    @MainActor
    func testPanoramaSuspendsAnActiveEnvironmentAndRestoresItOnReturn() async throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )
        guard let app = launchRegisteredMediaAfterOpeningDarkEnvironment(
            identifiers: identifiers
        ) else { return }
        let environmentCard = app.descendants(matching: .any)[
            "SenseZone-VolumeRoot"
        ].firstMatch
        guard requireHittable(
            environmentCard,
            named: "Environment Card Volume",
            timeout: 20
        ) else { return }

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let window = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 45
        ) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") != "none"
                && $0.string("environmentEffect") == "dark"
                && $0.bool("videoVisible") == true
        })
        let session = try XCTUnwrap(window.string("session"))
        let environmentID = try XCTUnwrap(window.string("environment"))
        let immersionAmount = try XCTUnwrap(window.double("immersionAmount"))
        let formatRevision = try XCTUnwrap(
            window.uint64("lastRendererInputFormatRevision")
        )
        attachState(window, name: "active-environment-window-state")

        let format = app.descendants(matching: .any)[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        guard requireHittable(format, named: "Video Format") else { return }
        format.tap()
        let panorama = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-360°"
        ].firstMatch
        guard requireHittable(panorama, named: "360 degree projection") else { return }
        panorama.tap()
        let apply = app.buttons["PlayerUI-VideoFormat-apply"].firstMatch
        guard requireHittable(apply, named: "Apply video format") else { return }
        apply.tap()

        let portal = try XCTUnwrap(waitForState(windowState, timeout: 30) {
            $0.string("presentation") == "portal"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("attached") == "portal"
                && $0.string("projection") == "equirectangular360"
                && ($0.uint64("lastRendererInputFormatRevision") ?? 0)
                    > formatRevision
                && $0.string("environment") == environmentID
                && $0.string("environmentEffect") == "dark"
                && $0.bool("videoVisible") == true
        })
        let portalComponentRevision = try XCTUnwrap(
            portal.uint64("videoComponentRevision")
        )
        let enterPanorama = app.descendants(matching: .any)[
            "PlayerUI-TopAction-resumePanorama"
        ].firstMatch
        guard requireHittable(enterPanorama, named: "Enter Panorama") else { return }
        enterPanorama.tap()
        guard requirePresentationRequest(
            in: app,
            windowState: windowState,
            targetPresentation: "panorama"
        ) else { return }

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let panoramaState = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "panorama"
                && $0.string("attached") == "panorama"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("panoramaReturnEnvironment") == environmentID
                && $0.string("panoramaReturnEnvironmentEffect") == "dark"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceRenderingReady") == true
                && $0.string("surfaceContentType") == "equirectangular"
        })
        XCTAssertTrue(
            app.descendants(matching: .any)["SenseZone-VolumeRoot"]
                .firstMatch.waitForNonExistence(timeout: 10),
            "Environment Card must close before Panorama becomes the active presentation."
        )
        XCTAssertEqual(panoramaState.string("session"), session)
        XCTAssertEqual(
            panoramaState.double("immersionAmount") ?? .nan,
            immersionAmount,
            accuracy: 0.001
        )
        let panoramaComponentRevision = try XCTUnwrap(
            panoramaState.uint64("videoComponentRevision")
        )
        XCTAssertEqual(panoramaComponentRevision, portalComponentRevision + 1)
        let panoramaRendererGraphRevision = try XCTUnwrap(
            panoramaState.uint64("lastRendererInputGraphRevision")
        )
        try await Task.sleep(for: .seconds(2))
        attachState(panoramaState, name: "panorama-suspended-environment-state")
        guard try requireGeneratedColorBarsAreWearerVisible(
            in: app,
            timeout: 5,
            attachmentName: "panorama-suspended-environment-visible-video"
        ) else { return }

        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Portal") else { return }
        exitSpatial.tap()
        try observeTransitionToMainWindow(
            app: app,
            windowSurface: windowState,
            sourcePresentation: "panorama-active-environment",
            targetPresentation: "portal",
            expectedChrome: "off"
        )
        let restored = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30
        ) {
            $0.string("presentation") == "portal"
                && $0.string("attached") == "portal"
                && $0.string("environment") == environmentID
                && $0.string("environmentEffect") == "dark"
                && $0.string("panoramaReturnEnvironment") == "inactive"
                && $0.bool("videoVisible") == true
                && $0.bool("componentReady") == true
                && $0.bool("displayedPixel") == true
                && $0.string("desiredImmersiveMode") == "portal"
                && $0.string("actualImmersiveMode") == "portal"
                && $0.string("desiredSpatialVideoMode") == "screen"
                && $0.string("actualSpatialVideoMode") == "screen"
                && $0.uint64("videoComponentRevision")
                    == panoramaComponentRevision
                && $0.uint64("boundVideoComponentRevision")
                    == $0.uint64("videoComponentRevision")
                && $0.uint64("rendererPixelVideoComponentRevision")
                    == $0.uint64("videoComponentRevision")
                && $0.uint64("rendererPixelStreamEpoch")
                    == $0.uint64("streamEpoch")
                && $0.uint64("lastRendererInputGraphRevision")
                    == panoramaRendererGraphRevision
        })
        XCTAssertEqual(restored.string("session"), session)
        try await Task.sleep(for: .seconds(2))
        attachState(restored, name: "panorama-restored-environment-state")
        attachScreenshot(from: app, name: "panorama-restored-environment")
        XCTAssertEqual(
            restored.double("immersionAmount") ?? .nan,
            immersionAmount,
            accuracy: 0.001
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-window-control-plane"]
                .firstMatch.waitForExistence(timeout: 10),
            "Window playback must be visible after returning from Panorama."
        )
    }

    @MainActor
    func testDockedTemporarilyUsesDefaultEnvironmentAndRestoresActiveEnvironmentOnReturn() async throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )
        let activeEnvironmentID = "scenic-two"
        let defaultEnvironmentID = "scenic-three"
        guard let app = launchRegisteredMediaAfterOpeningDarkEnvironment(
            identifiers: identifiers,
            defaultScenicEnvironmentTitle: "Scenic Environment 3",
            activeEnvironmentID: activeEnvironmentID
        ) else { return }
        let environmentCard = app.descendants(matching: .any)[
            "SenseZone-VolumeRoot"
        ].firstMatch
        guard requireHittable(
            environmentCard,
            named: "Environment Card Volume",
            timeout: 20
        ) else { return }

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let windowPlay = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        let window = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 45
        ) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == activeEnvironmentID
                && $0.string("environmentEffect") == "dark"
                && $0.string("environmentCardResidency") == "open"
                && $0.bool("videoVisible") == true
        })
        let session = try XCTUnwrap(window.string("session"))
        let environmentID = try XCTUnwrap(window.string("environment"))
        let immersionAmount = try XCTUnwrap(window.double("immersionAmount"))
        guard requireHittable(windowPlay, named: "Window Play/Pause") else { return }

        let dock = app.descendants(matching: .any)[
            "PlayerUI-TopAction-dock"
        ].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let light = app.buttons["PlayerUI-DockMenu-light"].firstMatch
        guard requireHittable(light, named: "Dock with Light Mode") else { return }
        light.tap()
        guard requirePresentationRequest(
            in: app,
            windowState: windowState,
            targetPresentation: "docked"
        ) else { return }

        let docked = try observeTransitionToSpatialPresentation(
            app: app,
            originalSurface: windowState,
            originalTransportControl: windowPlay,
            targetPresentation: "docked"
        )
        XCTAssertEqual(docked.string("session"), session)
        XCTAssertEqual(docked.string("attached"), "docked")
        XCTAssertEqual(docked.string("environment"), defaultEnvironmentID)
        XCTAssertNotEqual(docked.string("environment"), environmentID)
        XCTAssertEqual(docked.string("environmentEffect"), "light")
        XCTAssertEqual(docked.string("environmentCardResidency"), "closed")
        XCTAssertEqual(docked.bool("surfaceSettled"), true)
        XCTAssertEqual(docked.bool("surfaceRenderingReady"), true)
        XCTAssertEqual(docked.bool("surfaceAnchorMatched"), true)
        XCTAssertEqual(docked.string("surfaceParent"), "PlaybackSurfaceAnchor")
        XCTAssertEqual(
            docked.double("immersionAmount") ?? .nan,
            immersionAmount,
            accuracy: 0.001
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["SenseZone-VolumeRoot"]
                .firstMatch.waitForNonExistence(timeout: 10),
            "Environment Card must close before Docked becomes the active presentation."
        )
        try await Task.sleep(for: .seconds(2))
        attachState(docked, name: "docked-temporary-default-environment-state")
        attachScreenshot(from: app, name: "docked-temporary-default-environment")

        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return }
        exitSpatial.tap()
        try observeTransitionBackToWindow(
            app: app,
            windowSurface: windowState,
            sourcePresentation: "docked-temporary-default-environment"
        )
        let restored = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30
        ) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == environmentID
                && $0.string("environmentEffect") == "dark"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("videoVisible") == true
        })
        XCTAssertEqual(restored.string("session"), session)
        XCTAssertEqual(
            restored.double("immersionAmount") ?? .nan,
            immersionAmount,
            accuracy: 0.001
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-window-control-plane"]
                .firstMatch.waitForExistence(timeout: 10),
            "Window playback must be visible after returning from Docked."
        )
        try await Task.sleep(for: .seconds(2))
        attachState(restored, name: "docked-restored-active-environment-state")
        attachScreenshot(from: app, name: "docked-restored-active-environment")
    }

    @MainActor
    private func launchRegisteredMediaAfterOpeningDarkEnvironment(
        identifiers: [String],
        defaultScenicEnvironmentTitle: String? = nil,
        activeEnvironmentID: String = "scenic-one"
    ) -> XCUIApplication? {
        guard let identifier = identifiers.first else { return nil }
        let app = launchVisionProRegressionApp()

        guard let initialCard = waitForHittableRegisteredMediaCard(
            identifier: identifier,
            in: app,
            timeout: 30
        ) else {
            XCTFail(
                "Registered media was unavailable before format normalization."
            )
            return nil
        }
        initialCard.tap()
        let initialResume = app.buttons["PlayerUI-resumeDecision-primary"].firstMatch
        if initialResume.waitForExistence(timeout: 2) {
            initialResume.tap()
        }
        guard restoreWindowPlaybackIfSpatialPresentationIsActive(in: app),
              restoreFlatWindowFormatIfNeeded(in: app) else { return nil }

        let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
        guard requireHittable(
            back,
            named: "Return to Files after format normalization"
        ) else { return nil }
        back.tap()

        guard filterMediaLibrary(
            to: identifier,
            in: app
        ) else { return nil }

        if let defaultScenicEnvironmentTitle,
           selectDefaultScenicEnvironment(
               named: defaultScenicEnvironmentTitle,
               in: app
           ) == false {
            return nil
        }

        let environmentTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-environment"
        ].firstMatch
        guard requireHittable(environmentTab, named: "Environments") else { return nil }
        environmentTab.tap()

        let volume = app.descendants(matching: .any)["SenseZone-VolumeRoot"].firstMatch
        guard requireHittable(volume, named: "Environment Card Volume", timeout: 20) else {
            return nil
        }
        let carousel = app.descendants(matching: .any)[
            "EnvironmentCard-carousel"
        ].firstMatch
        guard requireHittable(
            carousel,
            named: "Environment Card carousel"
        ) else { return nil }
        let openIdentifier =
            "EnvironmentCard-button-environment-\(activeEnvironmentID)"
        var focusedActiveEnvironment: XCUIElement?
        for attempt in 0..<4 {
            if let open = firstHittableElement(
                matching: openIdentifier,
                in: app.buttons,
                timeout: 2
            ) {
                focusedActiveEnvironment = open
                break
            }
            if attempt < 3 {
                dragEnvironmentCarouselOneCardLeft(carousel)
            }
        }
        guard let open = focusedActiveEnvironment else {
            attachScreenshot(from: app, name: "active-environment-card-not-focused")
            XCTFail(
                "Environment Card carousel did not expose \(activeEnvironmentID)."
            )
            return nil
        }
        open.tap()
        guard waitForState(
            in: app,
            identifier: "PlayerUI-application-state",
            timeout: 30,
            where: {
                $0.string("environment") == activeEnvironmentID
                    && $0.string("environmentEffect") == "light"
                    && $0.string("immersiveSpaceResidency") == "open"
            }
        ) != nil else { return nil }

        guard let effect = firstHittableElement(
            matching: "EnvironmentCard-effect-\(activeEnvironmentID)",
            in: app.buttons,
            timeout: 3
        ) else {
            XCTFail("Switch Environment to Dark Mode did not become hittable.")
            return nil
        }
        effect.tap()

        guard waitForState(
            in: app,
            identifier: "PlayerUI-application-state",
            timeout: 30,
            where: {
            $0.string("environment") == activeEnvironmentID
                && $0.string("environmentEffect") == "dark"
                && $0.string("immersiveSpaceResidency") == "open"
            }
        ) != nil else { return nil }

        let filesTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-files"
        ].firstMatch
        guard requireHittable(filesTab, named: "Files") else { return nil }
        filesTab.tap()
        let card = app.buttons.matching(identifier: identifier).firstMatch
        guard requireHittable(
            card,
            named: "Filtered media while the Environment Card is open",
            timeout: 10
        ) else {
            attachScreenshot(
                from: app,
                name: "active-environment-media-card-not-hittable"
            )
            return nil
        }
        card.tap()
        let resume = app.buttons["PlayerUI-resumeDecision-primary"].firstMatch
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        if resume.waitForExistence(timeout: 3) == false,
           windowState.exists == false {
            attachScreenshot(
                from: app,
                name: "active-environment-media-first-spatial-tap-did-not-launch"
            )
            card.tap()
        }
        if resume.waitForExistence(timeout: 5) {
            resume.tap()
        }
        return app
    }

    private func dragEnvironmentCarouselOneCardLeft(
        _ carousel: XCUIElement
    ) {
        carousel.swipeLeft(velocity: .slow)
    }

    @MainActor
    private func filterMediaLibrary(
        to mediaCardIdentifier: String,
        in app: XCUIApplication
    ) -> Bool {
        let prefix = "MediaLibrary-grid-video-"
        guard mediaCardIdentifier.hasPrefix(prefix) else {
            XCTFail("Configured media identifier was not a video card.")
            return false
        }
        let filename = String(mediaCardIdentifier.dropFirst(prefix.count))
        let visibleName = (filename as NSString).deletingPathExtension
        let search = app.textFields[
            "FileBrowsing-FilesScreen-search"
        ].firstMatch
        guard requireHittable(search, named: "Media Library search") else {
            return false
        }
        search.tap()
        search.typeText(visibleName)

        let card = app.buttons.matching(
            identifier: mediaCardIdentifier
        ).firstMatch
        guard requireHittable(
            card,
            named: "Media filtered by its full filename"
        ) else {
            attachScreenshot(
                from: app,
                name: "active-environment-media-search-did-not-filter"
            )
            return false
        }
        return true
    }

    @MainActor
    private func observeTransitionToSpatialPresentation(
        app: XCUIApplication,
        originalSurface: XCUIElement,
        originalTransportControl: XCUIElement,
        targetPresentation: String
    ) throws -> RegressionStateSnapshot {
        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let deadline = Date().addingTimeInterval(20)
        let inconsistentSnapshotConfirmation: TimeInterval = 0.5
        var samples: [String] = []
        var observedTwoUsableInterfaces = false
        var observedTargetPreparation = false
        var observedMediaLoadingSpinner = false
        var twoUsableInterfacesStartedAt: Date?
        var lastWindowSnapshot = RegressionStateSnapshot(rawValue: "element-absent")
        var settledTargetSnapshot: RegressionStateSnapshot?

        while Date() < deadline {
            let targetStateExists = spatialState.exists
            let targetSnapshot = targetStateExists
                ? RegressionStateSnapshot(
                    rawValue: spatialState.value as? String ?? "value-unavailable"
                )
                : nil
            let windowExists = originalSurface.exists
            // Once the target control plane appears, committing the transition
            // can dismiss the source Window between an `exists` query and a
            // later `value` query. The target state is authoritative from that
            // point, so don't ask XCUI for a disappearing element's snapshot.
            let windowValue = windowExists && targetStateExists == false
                ? (originalSurface.value as? String ?? "value-unavailable")
                : (windowExists ? "not-read-after-target-appeared" : "element-absent")
            if windowExists && targetStateExists == false {
                lastWindowSnapshot = RegressionStateSnapshot(rawValue: windowValue)
            }
            let windowSnapshot = lastWindowSnapshot
            let windowUsable = windowExists
                && originalTransportControl.exists
                && originalTransportControl.isHittable
            let exitSpatialExists = exitSpatial.exists
            let exitSpatialFrame = exitSpatialExists ? exitSpatial.frame : .zero
            let targetUsable = exitSpatialExists
                && exitSpatial.isEnabled
                && exitSpatialFrame.width > 0
                && exitSpatialFrame.height > 0
                && targetSnapshot?.bool("controlsInteractive") == true
            let targetSettled = targetSnapshot?.string("presentation")
                    == targetPresentation
                && targetSnapshot?.string("attached") == targetPresentation
                && targetSnapshot?.bool("surfaceSettled") == true
                && (targetPresentation != "panorama"
                    || targetSnapshot?.string("surfaceContentType")
                        == "equirectangular")
            if windowSnapshot.string("surfacePresentation") == targetPresentation
                || targetSnapshot?.string("attached") == targetPresentation {
                observedTargetPreparation = true
            }
            if windowSnapshot.string("loadingSpinner") == "on"
                || targetSnapshot?.string("loadingSpinner") == "on" {
                observedMediaLoadingSpinner = true
            }
            samples.append(
                "\(Date().timeIntervalSince1970):windowExists=\(windowExists);windowUsable=\(windowUsable);targetUsable=\(targetUsable);windowState=\(windowValue);targetState=\(targetSnapshot?.rawValue ?? "element-absent")"
            )
            let now = Date()
            if windowUsable && targetUsable {
                let startedAt = twoUsableInterfacesStartedAt ?? now
                twoUsableInterfacesStartedAt = startedAt
                if now.timeIntervalSince(startedAt)
                    >= inconsistentSnapshotConfirmation {
                    observedTwoUsableInterfaces = true
                    break
                }
            } else {
                twoUsableInterfacesStartedAt = nil
            }
            if targetUsable && windowUsable == false && targetSettled {
                settledTargetSnapshot = targetSnapshot
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let timeline = XCTAttachment(string: samples.joined(separator: "\n"))
        timeline.name = "\(targetPresentation)-handoff-timeline"
        timeline.lifetime = .keepAlways
        add(timeline)
        if exitSpatial.exists == false || spatialState.exists == false {
            attachCurrentState(
                of: originalSurface,
                name: "\(targetPresentation)-handoff-window-state-at-failure"
            )
            attachCurrentState(
                of: spatialState,
                name: "\(targetPresentation)-handoff-target-state-at-failure"
            )
            attachScreenshot(
                from: app,
                name: "\(targetPresentation)-handoff-failure"
            )
        }
        XCTAssertFalse(
            observedTwoUsableInterfaces,
            "Window playback and the target attached controls were usable at the same time."
        )
        XCTAssertFalse(
            observedMediaLoadingSpinner,
            "A Presentation Transition must not show the media loading spinner."
        )
        XCTAssertTrue(
            observedTargetPreparation,
            "The target playback surface did not begin preparing while the source was fading."
        )
        let exitActionName = targetPresentation == "panorama"
            ? "Return to Portal"
            : "Return to Window"
        guard requireHittable(exitSpatial, named: exitActionName, timeout: 5) else {
            throw DeviceRegressionFailure.targetControlsUnavailable(targetPresentation)
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch.isHittable,
            "The Window and spatial playback interfaces must not both accept Presentation input."
        )
        return try XCTUnwrap(
            settledTargetSnapshot,
            "The target never produced one complete RealityKit settlement confirmation."
        )
    }

    @MainActor
    private func observeTransitionBackToWindow(
        app: XCUIApplication,
        windowSurface: XCUIElement,
        sourcePresentation: String
    ) throws {
        try observeTransitionToMainWindow(
            app: app,
            windowSurface: windowSurface,
            sourcePresentation: sourcePresentation,
            targetPresentation: "window",
            expectedChrome: "on"
        )
    }

    @MainActor
    private func observeTransitionToMainWindow(
        app: XCUIApplication,
        windowSurface: XCUIElement,
        sourcePresentation: String,
        targetPresentation: String,
        expectedChrome: String
    ) throws {
        let deadline = Date().addingTimeInterval(20)
        var samples: [String] = []
        var reachedMainWindow = false

        while Date() < deadline {
            let windowValue = windowSurface.exists
                ? (windowSurface.value as? String ?? "value-unavailable")
                : "element-absent"
            let windowSnapshot = RegressionStateSnapshot(rawValue: windowValue)
            let windowUsable = windowSurface.exists
                && windowSnapshot.string("presentation") == targetPresentation
                && windowSnapshot.string("transition") == "none"
                && windowSnapshot.string("chrome") == expectedChrome
                && windowSnapshot.bool("windowInteractive") == true
                && windowSnapshot.bool("videoVisible") == true
            samples.append(
                "\(Date().timeIntervalSince1970):windowUsable=\(windowUsable);windowState=\(windowValue)"
            )

            if windowUsable {
                reachedMainWindow = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let timeline = XCTAttachment(string: samples.joined(separator: "\n"))
        timeline.name = "\(sourcePresentation)-return-handoff-timeline"
        timeline.lifetime = .keepAlways
        add(timeline)
        if reachedMainWindow == false {
            attachCurrentState(
                of: windowSurface,
                name: "\(sourcePresentation)-return-window-state-at-failure"
            )
            attachScreenshot(
                from: app,
                name: "\(sourcePresentation)-return-handoff-failure"
            )
        }
        XCTAssertTrue(
            reachedMainWindow,
            "The \(targetPresentation) main-window presentation did not become the only usable interface after the Presentation Transition."
        )
    }
}
