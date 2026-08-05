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
    func testWindowSurfaceAndVisibleControlsDoNotCauseAnExtraVisibilityToggle() throws {
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

        let surfaceCoordinate = windowState.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)
        )
        surfaceCoordinate.tap()
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

        surfaceCoordinate.tap()
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

        let format = app.descendants(matching: .any)[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        guard requireHittable(format, named: "Window Video Format") else { return }
        format.tap()
        let cancelFormat = app.buttons["PlayerUI-VideoFormat-cancel"].firstMatch
        guard requireHittable(cancelFormat, named: "Cancel Video Format") else { return }
        _ = try XCTUnwrap(waitForState(windowState, timeout: 5) {
            $0.string("secondaryMenu") == "open"
                && $0.string("controls") == "shown"
        })

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
            $0.string("secondaryMenu") == "closed"
                && $0.string("projection") == initialProjection
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

        let more = app.descendants(matching: .any)[
            "PlayerUI-TopAction-more"
        ].firstMatch
        guard requireHittable(more, named: "Window More") else { return }
        more.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-menu-subtitles"]
                .firstMatch.waitForExistence(timeout: 5)
        )
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "More action"
        )
        attachScreenshot(from: app, name: "window-input-06-more")
        more.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-menu-subtitles"]
                .firstMatch.waitForNonExistence(timeout: 5)
        )
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "closing More"
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
        attachState(paused, name: "window-input-07-paused")
        XCTAssertEqual(playPause.label, "Play")
        assertControlsVisibility(
            "shown",
            remainsStableFor: 0.8,
            in: windowState,
            context: "Pause action"
        )

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
    func testWindowFadesWhileDockedPreparesThenDockedBecomesUsable() async throws {
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
        let windowPlay = app.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(windowPlay, named: "Window Play/Pause") else { return }
        attachScreenshot(from: app, name: "docked-handoff-01-window")

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let day = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        guard requireHittable(day, named: "Dock with Day") else { return }
        attachScreenshot(from: app, name: "docked-handoff-menu-open")
        day.tap()
        guard requirePresentationRequest(
            in: app,
            windowState: windowState,
            targetPresentation: "docked"
        ) else { return }

        let spatial = try observeTransitionToSpatialPresentation(
            app: app,
            originalSurface: windowState,
            originalTransportControl: windowPlay,
            targetPresentation: "docked"
        )
        XCTAssertEqual(spatial.string("session"), session)
        XCTAssertEqual(spatial.string("attached"), "docked")
        XCTAssertEqual(spatial.bool("surfaceSettled"), true)
        XCTAssertEqual(spatial.bool("surfaceRenderingReady"), true)
        XCTAssertEqual(spatial.bool("surfaceAnchorMatched"), true)
        XCTAssertEqual(spatial.string("surfaceParent"), "PlaybackSurfaceAnchor")
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertTrue(windowState.waitForNonExistence(timeout: 15))
        attachState(spatial, name: "docked-handoff-state")
        attachScreenshot(from: app, name: "docked-handoff-02-settled")
    }

    @MainActor
    func testDockReturnRemainsPausedUntilWindowPlayThenDisplaysContinuousFrames() async throws {
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
        attachState(playingWindow, name: "dock-return-01-window-playing")

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let day = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        guard requireHittable(day, named: "Dock with Day") else { return }
        day.tap()

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
        let docked = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.string("transition") == "none"
                && $0.string("attached") == "docked"
                && $0.bool("surfaceSettled") == true
                && $0.string("lifecycle")?.lowercased() == "paused"
                && abs($0.double("actualRate") ?? 1) < 0.001
        })
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
        attachState(returned, name: "dock-return-05-window-returned-paused")
        attachScreenshot(from: app, name: "dock-return-05-window-returned-paused")

        try await Task.sleep(for: .seconds(1))
        let returnedAfterObservation = RegressionStateSnapshot(
            rawValue: windowState.value as? String ?? ""
        )
        attachState(
            returnedAfterObservation,
            name: "dock-return-06-window-still-paused"
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
                && ($0.uint64("rendererInputs") ?? 0)
                    > (returnedAfterObservation.uint64("rendererInputs") ?? 0)
                && ($0.uint64("displayedFrameObservations") ?? 0)
                    >= (returnedAfterObservation.uint64("displayedFrameObservations") ?? 0) + 2
                && $0.string("error") == "none"
        })
        attachState(resumed, name: "dock-return-07-window-play-verified")
        attachScreenshot(from: app, name: "dock-return-07-window-play-verified")

        try await Task.sleep(for: .seconds(2))
        let continued = RegressionStateSnapshot(rawValue: windowState.value as? String ?? "")
        attachState(continued, name: "dock-return-08-window-continuing")
        attachScreenshot(from: app, name: "dock-return-08-window-continuing")
        XCTAssertEqual(continued.string("lifecycle")?.lowercased(), "playing")
        XCTAssertGreaterThan(continued.double("actualRate") ?? 0, 0.5)
        XCTAssertGreaterThan(
            continued.double("position") ?? 0,
            resumed.double("position") ?? 0,
            "Media time did not continue after the explicit Window Play."
        )
        XCTAssertGreaterThan(
            continued.uint64("rendererInputs") ?? 0,
            resumed.uint64("rendererInputs") ?? 0,
            "The returned Window renderer accepted no later video input."
        )
        XCTAssertGreaterThanOrEqual(
            continued.uint64("displayedFrameObservations") ?? 0,
            (resumed.uint64("displayedFrameObservations") ?? 0) + 2,
            "The returned Window renderer retained a static frame instead of displaying later frames."
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
    func testDockedControlsDeckRemainsClickableAfterThePresentationTransition() throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredSpatialMedia(identifier: identifier) else { return }
        guard restoreWindowPlaybackIfSpatialPresentationIsActive(in: app) else { return }
        guard restoreFlatWindowFormatIfNeeded(in: app) else { return }

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        _ = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 45
        ) {
            $0.string("attached") == "window"
                && $0.string("lifecycle")?.lowercased() == "playing"
        })

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let day = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        guard requireHittable(day, named: "Dock with Day") else { return }
        day.tap()
        let playPause = app.descendants(matching: .any)["PlayerPanel-button-play"].firstMatch
        guard requireHittable(playPause, named: "Docked Play/Pause") else { return }
        let labelBeforeTap = playPause.label
        playPause.tap()
        XCTAssertNotEqual(playPause.label, labelBeforeTap)
        attachScreenshot(from: app, name: "docked-deck-clicked-after-transition")
    }

    @MainActor
    func testWindowFadesWhilePanoramaPreparesThenPanoramaBecomesUsable() async throws {
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
        let rendererGraphRevisionBeforeTransition = try XCTUnwrap(
            before.uint64("lastRendererInputGraphRevision")
        )
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
        XCTAssertEqual(
            spatial.uint64("lastRendererInputGraphRevision"),
            rendererGraphRevisionBeforeTransition,
            "Window-to-Panorama must bind the target component to the existing renderer graph."
        )
        XCTAssertEqual(spatial.string("attached"), "panorama")
        XCTAssertEqual(spatial.string("rendererConsumer"), "panorama")
        XCTAssertEqual(spatial.string("rendererConsumerEntity"), "present")
        XCTAssertNotNil(
            spatial.double("sourceRemovalToTargetBindSeconds"),
            "The physical transition must retain the measured interval from source component removal to target component binding."
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(spatial.double("surfaceOpacity")),
            0.99,
            "The Panorama surface must be fully visible after the transition settles."
        )
        XCTAssertEqual(spatial.string("environment"), "none")
        XCTAssertEqual(spatial.string("environmentEffect"), "none")
        XCTAssertEqual(spatial.string("panoramaReturnEnvironment"), "none")
        XCTAssertEqual(spatial.string("panoramaReturnEnvironmentEffect"), "none")
        XCTAssertEqual(spatial.string("environmentCardResidency"), "closed")
        XCTAssertEqual(spatial.bool("skyboxActive"), false)
        XCTAssertEqual(spatial.string("skyboxOpacity"), "none")
        XCTAssertEqual(spatial.bool("surfaceSettled"), true)
        XCTAssertEqual(spatial.bool("surfaceRenderingReady"), true)
        XCTAssertEqual(spatial.string("surfaceContentType"), "equirectangular")
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertTrue(windowState.waitForNonExistence(timeout: 15))
        attachState(spatial, name: "panorama-handoff-state")
        try await Task.sleep(for: .seconds(2))
        guard try requireGeneratedColorBarsAreWearerVisible(
            in: app,
            timeout: 5,
            attachmentName: "panorama-handoff-02-settled-visible-video"
        ) else { return }

        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        let windowPresentationControl = app.descendants(matching: .any)[
            "PlayerUI-TopAction-resumePanorama"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return }
        exitSpatial.tap()
        try observeTransitionBackToWindow(
            app: app,
            spatialControl: exitSpatial,
            windowSurface: windowState,
            windowPresentationControl: windowPresentationControl,
            sourcePresentation: "panorama"
        )
        let restored = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30
        ) {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("attached") == "window"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("panoramaReturnEnvironment") == "inactive"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("skyboxActive") == false
                && $0.bool("videoVisible") == true
                && $0.string("desiredImmersiveMode") == "portal"
                && $0.string("actualImmersiveMode") == "portal"
                && $0.string("desiredViewingMode") == "mono"
                && $0.string("actualViewingMode") == "mono"
                && $0.string("desiredSpatialVideoMode") == "screen"
                && $0.string("actualSpatialVideoMode") == "screen"
        })
        XCTAssertEqual(restored.string("session"), session)
        try await Task.sleep(for: .seconds(2))
        attachState(restored, name: "panorama-none-environment-window-return-state")
        attachScreenshot(from: app, name: "panorama-none-environment-window-return")
    }

    @MainActor
    func testPanoramaSuspendsAnActiveEnvironmentAndRestoresItOnReturn() async throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )
        guard let app = launchRegisteredMediaAfterOpeningNightEnvironment(
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
                && $0.string("environment") == "enchron"
                && $0.string("environmentEffect") == "night"
                && $0.bool("skyboxActive") == true
                && abs(($0.double("skyboxOpacity") ?? .nan) - 0.35) < 0.001
                && $0.bool("videoVisible") == true
        })
        let session = try XCTUnwrap(window.string("session"))
        let immersionAmount = try XCTUnwrap(window.double("immersionAmount"))
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
                && $0.string("panoramaReturnEnvironment") == "enchron"
                && $0.string("panoramaReturnEnvironmentEffect") == "night"
                && $0.string("environmentCardResidency") == "closed"
                && $0.string("skyboxOpacity") == "none"
                && $0.bool("skyboxActive") == false
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
        let panoramaStreamEpoch = try XCTUnwrap(
            panoramaState.uint64("streamEpoch")
        )
        let panoramaRendererInputs = try XCTUnwrap(
            panoramaState.uint64("rendererInputs")
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
        let windowPresentationControl = app.descendants(matching: .any)[
            "PlayerUI-TopAction-resumePanorama"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return }
        exitSpatial.tap()
        try observeTransitionBackToWindow(
            app: app,
            spatialControl: exitSpatial,
            windowSurface: windowState,
            windowPresentationControl: windowPresentationControl,
            sourcePresentation: "panorama-active-environment"
        )
        let restored = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30
        ) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == "enchron"
                && $0.string("environmentEffect") == "night"
                && $0.string("panoramaReturnEnvironment") == "inactive"
                && $0.bool("skyboxActive") == true
                && abs(($0.double("skyboxOpacity") ?? .nan) - 0.35) < 0.001
                && $0.bool("videoVisible") == true
                && $0.bool("componentReady") == true
                && $0.bool("displayedPixel") == true
                && $0.string("desiredImmersiveMode") == "portal"
                && $0.string("actualImmersiveMode") == "portal"
                && $0.string("desiredViewingMode") == "mono"
                && $0.string("actualViewingMode") == "mono"
                && $0.string("desiredSpatialVideoMode") == "screen"
                && $0.string("actualSpatialVideoMode") == "screen"
                && ($0.uint64("videoComponentRevision") ?? 0)
                    > panoramaComponentRevision
                && $0.uint64("boundVideoComponentRevision")
                    == $0.uint64("videoComponentRevision")
                && $0.uint64("rendererPixelVideoComponentRevision")
                    == $0.uint64("videoComponentRevision")
                && $0.uint64("rendererPixelStreamEpoch")
                    == $0.uint64("streamEpoch")
                && ($0.uint64("streamEpoch") ?? 0) > panoramaStreamEpoch
                && ($0.uint64("rendererInputs") ?? 0) > panoramaRendererInputs
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
    func testDockedInheritsActiveEnvironmentAndRestoresItOnReturn() async throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )
        guard let app = launchRegisteredMediaAfterOpeningNightEnvironment(
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
                && $0.string("environment") == "enchron"
                && $0.string("environmentEffect") == "night"
                && $0.string("environmentCardResidency") == "open"
                && $0.bool("skyboxActive") == true
                && abs(($0.double("skyboxOpacity") ?? .nan) - 0.35) < 0.001
                && $0.bool("videoVisible") == true
        })
        let session = try XCTUnwrap(window.string("session"))
        let immersionAmount = try XCTUnwrap(window.double("immersionAmount"))
        guard requireHittable(windowPlay, named: "Window Play/Pause") else { return }

        let dock = app.descendants(matching: .any)[
            "PlayerUI-TopAction-dock"
        ].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let day = app.descendants(matching: .any)[
            "PlayerUI-DockMenu-day"
        ].firstMatch
        guard requireHittable(day, named: "Dock with Day") else { return }
        day.tap()
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
        XCTAssertEqual(docked.string("environment"), "enchron")
        XCTAssertEqual(docked.string("environmentEffect"), "night")
        XCTAssertEqual(docked.string("environmentCardResidency"), "closed")
        XCTAssertEqual(docked.bool("skyboxActive"), true)
        XCTAssertEqual(
            docked.double("skyboxOpacity") ?? .nan,
            0.35,
            accuracy: 0.001
        )
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
        attachState(docked, name: "docked-inherited-environment-state")
        attachScreenshot(from: app, name: "docked-inherited-environment")

        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        let windowPresentationControl = app.descendants(matching: .any)[
            "PlayerUI-TopAction-dock"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return }
        exitSpatial.tap()
        try observeTransitionBackToWindow(
            app: app,
            spatialControl: exitSpatial,
            windowSurface: windowState,
            windowPresentationControl: windowPresentationControl,
            sourcePresentation: "docked-active-environment"
        )
        let restored = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-window-control-plane",
            timeout: 30
        ) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == "enchron"
                && $0.string("environmentEffect") == "night"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("skyboxActive") == true
                && abs(($0.double("skyboxOpacity") ?? .nan) - 0.35) < 0.001
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
    private func launchRegisteredMediaAfterOpeningNightEnvironment(
        identifiers: [String]
    ) -> XCUIApplication? {
        guard let identifier = identifiers.first else { return nil }
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_SPATIAL_ACCEPTANCE"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launch()

        let initialCard = app.descendants(matching: .any)[identifier].firstMatch
        guard requireHittable(
            initialCard,
            named: "Registered media before format normalization",
            timeout: 30
        ) else { return nil }
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

        let environmentTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-environment"
        ].firstMatch
        guard requireHittable(environmentTab, named: "Environments") else { return nil }
        environmentTab.tap()

        let volume = app.descendants(matching: .any)["SenseZone-VolumeRoot"].firstMatch
        guard requireHittable(volume, named: "Environment Card Volume", timeout: 20) else {
            return nil
        }
        let effect = app.descendants(matching: .any)[
            "EnvironmentCard-effect"
        ].firstMatch
        guard requireHittable(effect, named: "Switch Environment to Night") else {
            return nil
        }
        effect.tap()
        let open = app.descendants(matching: .any)[
            "EnvironmentCard-button-environment"
        ].firstMatch
        guard requireHittable(open, named: "Open Environment") else { return nil }
        open.tap()

        guard waitForState(
            in: app,
            identifier: "PlayerUI-application-state",
            timeout: 30,
            where: {
            $0.string("environment") == "enchron"
                && $0.string("environmentEffect") == "night"
                && $0.string("immersiveSpaceResidency") == "open"
                && $0.bool("skyboxActive") == true
            }
        ) != nil else { return nil }

        let filesTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-files"
        ].firstMatch
        guard requireHittable(filesTab, named: "Files") else { return nil }
        filesTab.tap()
        guard let card = mediaCardWithTapPointOutsideEnvironmentCard(
            identifiers: identifiers,
            in: app,
            timeout: 30
        ) else {
            attachScreenshot(
                from: app,
                name: "active-environment-no-exposed-media-card"
            )
            XCTFail(
                "No configured media card had an exposed tap point outside the Environment Card."
            )
            return nil
        }
        card.coordinate.tap()
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
            card.coordinate.tap()
        }
        if resume.waitForExistence(timeout: 5) {
            resume.tap()
        }
        return app
    }

    @MainActor
    private func mediaCardWithTapPointOutsideEnvironmentCard(
        identifiers: [String],
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> (element: XCUIElement, coordinate: XCUICoordinate)? {
        let environmentCard = app.descendants(matching: .any)[
            "SenseZone-VolumeRoot"
        ].firstMatch
        guard environmentCard.waitForExistence(timeout: timeout) else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let environmentFrame = environmentCard.frame.insetBy(dx: -12, dy: -12)
            for identifier in identifiers {
                let mediaCard = app.descendants(matching: .any)[identifier].firstMatch
                guard mediaCard.exists, mediaCard.isEnabled, mediaCard.isHittable else {
                    continue
                }
                let mediaFrame = mediaCard.frame
                let visibleFrame = mediaFrame.intersection(app.frame)
                guard visibleFrame.isNull == false,
                      visibleFrame.width >= 24,
                      visibleFrame.maxY > environmentFrame.maxY + 24 else {
                    continue
                }
                let targetY = min(
                    visibleFrame.maxY - 12,
                    max(environmentFrame.maxY + 12, visibleFrame.midY)
                )
                guard targetY > environmentFrame.maxY,
                      mediaFrame.height > 0 else { continue }
                let normalizedY = (targetY - mediaFrame.minY) / mediaFrame.height
                return (
                    mediaCard,
                    mediaCard.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedY)
                    )
                )
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
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
        var observedWindowPortalToProgressiveChange = targetPresentation != "panorama"
        var twoUsableInterfacesStartedAt: Date?

        while Date() < deadline {
            let windowExists = originalSurface.exists
            let windowValue = windowExists
                ? (originalSurface.value as? String ?? "value-unavailable")
                : "element-absent"
            let windowSnapshot = RegressionStateSnapshot(rawValue: windowValue)
            let windowUsable = windowExists
                && originalTransportControl.exists
                && windowSnapshot.bool("windowInteractive") == true
            let exitSpatialExists = exitSpatial.exists
            let exitSpatialFrame = exitSpatialExists ? exitSpatial.frame : .zero
            let targetSnapshot = spatialState.exists
                ? RegressionStateSnapshot(
                    rawValue: spatialState.value as? String ?? "value-unavailable"
                )
                : nil
            let targetUsable = exitSpatialExists
                && exitSpatial.isEnabled
                && exitSpatialFrame.width > 0
                && exitSpatialFrame.height > 0
                && targetSnapshot?.bool("controlsInteractive") == true
            if windowSnapshot.string("surfacePresentation") == targetPresentation {
                observedTargetPreparation = true
            }
            if windowSnapshot.bool("windowPortalToProgressiveChangeConfirmed") == true {
                observedWindowPortalToProgressiveChange = true
            }
            if windowSnapshot.string("loadingSpinner") == "on" {
                observedMediaLoadingSpinner = true
            }
            samples.append(
                "\(Date().timeIntervalSince1970):windowExists=\(windowExists);windowUsable=\(windowUsable);targetUsable=\(targetUsable);windowState=\(windowValue)"
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
            if targetUsable && windowUsable == false {
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
            "Window playback and the target Player Controls Window were usable at the same time."
        )
        XCTAssertFalse(
            observedMediaLoadingSpinner,
            "A Presentation Transition must not show the media loading spinner."
        )
        XCTAssertTrue(
            observedTargetPreparation,
            "The target playback surface did not begin preparing while the source was fading."
        )
        XCTAssertTrue(
            observedWindowPortalToProgressiveChange,
            "Panorama must wait for the Window VideoPlayerComponent to report its Portal-to-progressive change."
        )
        guard requireHittable(exitSpatial, named: "Return to Window", timeout: 5) else {
            throw DeviceRegressionFailure.targetControlsUnavailable(targetPresentation)
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch.isHittable,
            "The Window and spatial playback interfaces must not both accept Presentation input."
        )
        return try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            $0.string("presentation") == targetPresentation
                && $0.string("attached") == targetPresentation
                && $0.bool("surfaceSettled") == true
                && (targetPresentation != "panorama"
                    || $0.string("surfaceContentType") == "equirectangular")
        })
    }

    @MainActor
    private func observeTransitionBackToWindow(
        app: XCUIApplication,
        spatialControl: XCUIElement,
        windowSurface: XCUIElement,
        windowPresentationControl: XCUIElement,
        sourcePresentation: String
    ) throws {
        let deadline = Date().addingTimeInterval(20)
        let inconsistentSnapshotConfirmation: TimeInterval = 0.5
        var samples: [String] = []
        var observedTwoUsableInterfaces = false
        var twoUsableInterfacesStartedAt: Date?
        var reachedWindow = false

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch

        while Date() < deadline {
            let spatialFrame = spatialControl.exists ? spatialControl.frame : .zero
            let spatialValue = spatialState.exists
                ? (spatialState.value as? String ?? "value-unavailable")
                : "element-absent"
            let spatialSnapshot = RegressionStateSnapshot(rawValue: spatialValue)
            let spatialUsable = spatialControl.exists
                && spatialControl.isEnabled
                && spatialFrame.width > 0
                && spatialFrame.height > 0
                && spatialSnapshot.bool("controlsInteractive") == true
            let windowValue = windowSurface.exists
                ? (windowSurface.value as? String ?? "value-unavailable")
                : "element-absent"
            let windowSnapshot = RegressionStateSnapshot(rawValue: windowValue)
            let windowFrame = windowPresentationControl.exists
                ? windowPresentationControl.frame
                : .zero
            let windowUsable = windowSurface.exists
                && windowPresentationControl.exists
                && windowPresentationControl.isEnabled
                && windowFrame.width > 0
                && windowFrame.height > 0
                && windowSnapshot.string("chrome") == "on"
                && windowSnapshot.bool("windowInteractive") == true
                && windowSnapshot.bool("videoVisible") == true
            samples.append(
                "\(Date().timeIntervalSince1970):spatialUsable=\(spatialUsable);windowUsable=\(windowUsable);windowState=\(windowValue)"
            )

            let now = Date()
            if spatialUsable && windowUsable {
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
            if windowUsable && spatialUsable == false {
                reachedWindow = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let timeline = XCTAttachment(string: samples.joined(separator: "\n"))
        timeline.name = "\(sourcePresentation)-return-handoff-timeline"
        timeline.lifetime = .keepAlways
        add(timeline)
        if reachedWindow == false {
            attachCurrentState(
                of: windowSurface,
                name: "\(sourcePresentation)-return-window-state-at-failure"
            )
            attachScreenshot(
                from: app,
                name: "\(sourcePresentation)-return-handoff-failure"
            )
        }
        XCTAssertFalse(
            observedTwoUsableInterfaces,
            "Player Controls Window and Window playback remained usable at the same time."
        )
        XCTAssertTrue(
            reachedWindow,
            "Window playback did not become the only usable interface after the Presentation Transition."
        )
    }
}
