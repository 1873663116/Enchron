import Foundation
import XCTest

nonisolated final class DockedPlacementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Docked placement regression requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testDockedLightModeAndDarkModeUseOneStableEnvironmentIdentity() async throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredSpatialMedia(identifier: identifier) else { return }
        guard restoreWindowPlaybackIfSpatialPresentationIsActive(in: app),
              restoreFlatWindowFormatIfNeeded(in: app) else { return }

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let baseline = try XCTUnwrap(waitForState(windowState, timeout: 30) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
        })
        let session = try XCTUnwrap(baseline.string("session"))

        guard enterDocked(in: app, effect: "dark") else { return }
        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let dark = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.string("environment") != "none"
                && $0.string("environmentEffect") == "dark"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceAnchorMatched") == true
                && $0.bool("surfaceRenderingReady") == true
        })
        let environmentIdentity = try XCTUnwrap(dark.string("environment"))
        XCTAssertEqual(dark.string("session"), session)
        attachState(dark, name: "docked-dark-state")
        try await Task.sleep(for: .seconds(2))
        attachScreenshot(from: app, name: "docked-dark")

        guard returnToWindow(in: app) else { return }
        let afterDark = try XCTUnwrap(waitForState(windowState, timeout: 30) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
        })
        XCTAssertEqual(afterDark.string("session"), session)
        attachState(afterDark, name: "window-after-temporary-dark-environment")

        guard enterDocked(in: app, effect: "light") else { return }
        let light = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.string("environment") == environmentIdentity
                && $0.string("environmentEffect") == "light"
                && $0.string("environmentCardResidency") == "closed"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceAnchorMatched") == true
                && $0.bool("surfaceRenderingReady") == true
        })
        XCTAssertEqual(light.string("session"), session)
        attachState(light, name: "docked-light-state")
        try await Task.sleep(for: .seconds(2))
        attachScreenshot(from: app, name: "docked-light")

        guard returnToWindow(in: app) else { return }
        let afterLight = try XCTUnwrap(waitForState(windowState, timeout: 30) {
            $0.string("presentation") == "window"
                && $0.string("attached") == "window"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
        })
        XCTAssertEqual(afterLight.string("session"), session)
        attachState(afterLight, name: "window-after-temporary-light-environment")
        attachScreenshot(from: app, name: "window-after-temporary-dock-environments")
        attachHumanReviewBoundary(
            "Compare the Light Mode and Dark Mode recording segments for the same Environment identity and confirm the effect changes the visible environment without obscuring playback.",
            name: "docked-light-dark-environment-human-review"
        )
    }

    @MainActor
    func testDockedPlacementPersistsAcrossSessionsAndProcessRestart() async throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 2
        )
        guard let app = launchRegisteredSpatialMedia(identifier: identifiers[0]) else { return }
        guard enterDocked(in: app) else { return }

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let initial = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceAnchorMatched") == true
        })
        assertSurfaceMatchesPlacement(initial)

        let settings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        guard requireHittable(settings, named: "Docked Settings") else { return }
        settings.tap()

        let size = app.descendants(matching: .any)[
            "PlayerPanel-ScreenSize-slider"
        ].firstMatch
        let distance = app.descendants(matching: .any)[
            "PlayerPanel-Distance-slider"
        ].firstMatch
        let elevation = app.descendants(matching: .any)[
            "PlayerPanel-Elevation-slider"
        ].firstMatch

        let initialScale = try XCTUnwrap(initial.double("screenScale"))
        let initialDistance = try XCTUnwrap(initial.double("screenDistance"))
        let initialElevation = try XCTUnwrap(initial.double("screenElevation"))
        dragDetentedSlider(
            size,
            from: normalized(initialScale, lower: 2, upper: 6),
            to: 0.75,
            named: "Screen Size"
        )
        dragDetentedSlider(
            distance,
            from: normalized(initialDistance, lower: 6, upper: 30),
            to: 0.75,
            named: "Distance"
        )
        dragDetentedSlider(
            elevation,
            from: normalized(initialElevation, lower: 0, upper: 90),
            to: 0.75,
            named: "Elevation"
        )

        let adjusted = try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            abs(($0.double("screenScale") ?? initialScale) - initialScale) > 0.1
                && abs(
                    ($0.double("screenDistance") ?? initialDistance)
                        - initialDistance
                ) > 0.1
                && abs(
                    ($0.double("screenElevation") ?? initialElevation)
                        - initialElevation
                ) > 1
                && $0.bool("surfaceSettled") == true
        })
        assertSurfaceMatchesPlacement(adjusted)
        attachState(adjusted, name: "docked-placement-adjusted")
        attachScreenshot(from: app, name: "docked-placement-01-adjusted")

        let adjustedScale = try XCTUnwrap(adjusted.double("screenScale"))
        let adjustedDistance = try XCTUnwrap(adjusted.double("screenDistance"))
        let adjustedElevation = try XCTUnwrap(adjusted.double("screenElevation"))
        let firstSession = try XCTUnwrap(adjusted.string("session"))
        guard returnToWindow(in: app) else { return }
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
        guard requireHittable(back, named: "Back to Media Library") else { return }
        back.tap()
        guard let secondCard = waitForHittableRegisteredMediaCard(
            identifier: identifiers[1],
            in: app,
            timeout: 30
        ) else {
            XCTFail("Second registered media was unavailable for placement persistence.")
            return
        }
        secondCard.tap()
        resolveResumeDecisionIfNeeded(in: app)
        _ = try XCTUnwrap(waitForState(windowState, timeout: 60) {
            $0.string("attached") == "window"
                && $0.string("session") != firstSession
                && $0.bool("displayedPixel") == true
        })

        guard enterDocked(in: app) else { return }
        let nextSession = try XCTUnwrap(waitForState(spatialState, timeout: 90) {
            $0.string("presentation") == "docked"
                && abs(
                    ($0.double("screenScale") ?? 0) - adjustedScale
                ) < 0.001
                && abs(
                    ($0.double("screenDistance") ?? 0) - adjustedDistance
                ) < 0.001
                && abs(
                    ($0.double("screenElevation") ?? 0) - adjustedElevation
                ) < 0.001
        })
        XCTAssertNotEqual(nextSession.string("session"), firstSession)
        assertSurfaceMatchesPlacement(nextSession)
        attachState(nextSession, name: "docked-placement-restored-new-session")

        app.terminate()
        app.launch()
        guard let relaunchedCard = waitForHittableRegisteredMediaCard(
            identifier: identifiers[0],
            in: app,
            timeout: 30
        ) else {
            XCTFail("Registered media was unavailable after the App process restart.")
            return
        }
        relaunchedCard.tap()
        resolveResumeDecisionIfNeeded(in: app)
        guard enterDocked(in: app) else { return }
        let afterProcessRestart = try XCTUnwrap(waitForState(spatialState, timeout: 90) {
            $0.string("presentation") == "docked"
                && abs(
                    ($0.double("screenScale") ?? 0) - adjustedScale
                ) < 0.001
                && abs(
                    ($0.double("screenDistance") ?? 0) - adjustedDistance
                ) < 0.001
                && abs(
                    ($0.double("screenElevation") ?? 0) - adjustedElevation
                ) < 0.001
        })
        assertSurfaceMatchesPlacement(afterProcessRestart)
        attachState(afterProcessRestart, name: "docked-placement-restored-process-restart")
        attachScreenshot(from: app, name: "docked-placement-02-restored-process-restart")

        let restoredSettings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        guard requireHittable(restoredSettings, named: "Docked Settings after return") else {
            return
        }
        restoredSettings.tap()
        let reset = app.buttons["PlayerPanel-DockedPlacement-reset"].firstMatch
        guard requireHittable(reset, named: "Restore Defaults") else { return }
        reset.tap()

        let resetState = try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            abs(($0.double("screenScale") ?? .nan) - initialScale) < 0.001
                && abs(($0.double("screenDistance") ?? .nan) - initialDistance) < 0.001
                && abs(($0.double("screenElevation") ?? .nan) - initialElevation) < 0.001
        })
        assertSurfaceMatchesPlacement(resetState)
        attachState(resetState, name: "docked-placement-restored-defaults")
        attachScreenshot(from: app, name: "docked-placement-03-restored-defaults")
        attachHumanReviewBoundary(
            "Review adjustment, new Media Session, process restart, and Restore Defaults segments for actual spatial movement and stable placement rather than state-only persistence.",
            name: "docked-placement-persistence-human-review"
        )
    }

    @MainActor
    func testDockedPlacementIsolatedByEnvironmentAndSharedAcrossEffects() async throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        guard let app = launchRegisteredSpatialMedia(identifier: identifier) else { return }
        guard restoreWindowPlaybackIfSpatialPresentationIsActive(in: app),
              restoreFlatWindowFormatIfNeeded(in: app),
              enterDocked(in: app, effect: "light") else { return }

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let initial = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.string("environment") == "ocean"
                && $0.string("environmentEffect") == "light"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceAnchorMatched") == true
        })
        let initialScale = try XCTUnwrap(initial.double("screenScale"))
        let initialDistance = try XCTUnwrap(initial.double("screenDistance"))
        let initialElevation = try XCTUnwrap(initial.double("screenElevation"))

        let settings = app.buttons["PlayerPanel-button-settings"].firstMatch
        guard requireHittable(settings, named: "Docked Settings") else { return }
        settings.tap()
        dragDetentedSlider(
            app.descendants(matching: .any)[
                "PlayerPanel-ScreenSize-slider"
            ].firstMatch,
            from: normalized(initialScale, lower: 2, upper: 6),
            to: 0.75,
            named: "Screen Size"
        )
        dragDetentedSlider(
            app.descendants(matching: .any)[
                "PlayerPanel-Distance-slider"
            ].firstMatch,
            from: normalized(initialDistance, lower: 6, upper: 30),
            to: 0.75,
            named: "Distance"
        )
        dragDetentedSlider(
            app.descendants(matching: .any)[
                "PlayerPanel-Elevation-slider"
            ].firstMatch,
            from: normalized(initialElevation, lower: 0, upper: 90),
            to: 0.75,
            named: "Elevation"
        )

        let adjusted = try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            abs(($0.double("screenScale") ?? initialScale) - initialScale) > 0.1
                && abs(
                    ($0.double("screenDistance") ?? initialDistance)
                        - initialDistance
                ) > 0.1
                && abs(
                    ($0.double("screenElevation") ?? initialElevation)
                        - initialElevation
                ) > 1
                && $0.bool("surfaceSettled") == true
        })
        let adjustedScale = try XCTUnwrap(adjusted.double("screenScale"))
        let adjustedDistance = try XCTUnwrap(adjusted.double("screenDistance"))
        let adjustedElevation = try XCTUnwrap(adjusted.double("screenElevation"))
        assertSurfaceMatchesPlacement(adjusted)
        attachState(adjusted, name: "docked-placement-ocean-light-adjusted")

        guard returnToWindow(in: app),
              enterDocked(in: app, effect: "default") else { return }

        let isolated = try XCTUnwrap(waitForState(spatialState, timeout: 60) {
            $0.string("presentation") == "docked"
                && $0.string("environment") == "quiet-room"
                && $0.string("environmentEffect") == "none"
                && abs(($0.double("screenScale") ?? adjustedScale) - adjustedScale) > 0.1
                && abs(
                    ($0.double("screenDistance") ?? adjustedDistance)
                        - adjustedDistance
                ) > 0.1
                && abs(
                    ($0.double("screenElevation") ?? adjustedElevation)
                        - adjustedElevation
                ) > 1
                && $0.bool("surfaceSettled") == true
        })
        assertSurfaceMatchesPlacement(isolated)
        attachState(isolated, name: "docked-placement-quiet-room-isolated")
        attachScreenshot(from: app, name: "docked-placement-04-quiet-room-isolated")

        guard returnToWindow(in: app),
              enterDocked(in: app, effect: "dark") else { return }

        let sharedAcrossEffects = try XCTUnwrap(waitForState(spatialState, timeout: 60) {
            $0.string("presentation") == "docked"
                && $0.string("environment") == "ocean"
                && $0.string("environmentEffect") == "dark"
                && abs(($0.double("screenScale") ?? 0) - adjustedScale) < 0.001
                && abs(
                    ($0.double("screenDistance") ?? 0) - adjustedDistance
                ) < 0.001
                && abs(
                    ($0.double("screenElevation") ?? 0) - adjustedElevation
                ) < 0.001
                && $0.bool("surfaceSettled") == true
        })
        assertSurfaceMatchesPlacement(sharedAcrossEffects)
        attachState(
            sharedAcrossEffects,
            name: "docked-placement-ocean-dark-restored"
        )
        attachScreenshot(
            from: app,
            name: "docked-placement-05-ocean-dark-restored"
        )
        attachHumanReviewBoundary(
            "Review the Ocean Light Mode adjustment, Quiet Room isolation, and Ocean Dark Mode restoration segments for actual spatial placement changes.",
            name: "docked-placement-environment-isolation-human-review"
        )
    }

    @MainActor
    private func enterDocked(
        in app: XCUIApplication,
        effect: String = "light"
    ) -> Bool {
        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock", timeout: 30) else { return false }
        dock.tap()
        let effectButton = app.buttons.matching(
            identifier: "PlayerUI-DockMenu-\(effect)"
        ).firstMatch
        guard requireHittable(
            effectButton,
            named: "Dock with \(effect.capitalized)"
        ) else { return false }
        attachScreenshot(from: app, name: "docked-placement-menu-open")
        effectButton.tap()
        let exit = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard requirePresentationRequest(
            in: app,
            windowState: windowState,
            targetPresentation: "docked"
        ) else { return false }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if exit.exists, exit.isHittable, spatialState.exists {
                return true
            }
            if app.alerts["Failed to Load"].firstMatch.exists
                || app.alerts["Playback Error"].firstMatch.exists {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        attachCurrentState(of: windowState, name: "docked-entry-window-state-at-failure")
        attachCurrentState(of: spatialState, name: "docked-entry-target-state-at-failure")
        attachScreenshot(from: app, name: "docked-entry-failure")
        XCTFail("Docked playback and its attached controls did not become usable.")
        return false
    }

    @MainActor
    private func returnToWindow(in app: XCUIApplication) -> Bool {
        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return false }
        exitSpatial.tap()

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        guard waitForState(windowState, timeout: 30, where: {
            $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("attached") == "window"
                && $0.bool("videoVisible") == true
                && $0.string("chrome") == "on"
        }) != nil else {
            attachCurrentState(of: windowState, name: "light-dark-window-return-state-at-failure")
            attachScreenshot(from: app, name: "light-dark-window-return-failure")
            XCTFail("Window playback did not become usable after leaving Docked playback.")
            return false
        }
        return true
    }

    private func normalized(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> CGFloat {
        CGFloat((value - lower) / (upper - lower))
    }

    private func assertSurfaceMatchesPlacement(
        _ state: RegressionStateSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let distance = state.double("screenDistance") ?? .nan
        let elevation = state.double("screenElevation") ?? .nan
        let scale = state.double("screenScale") ?? .nan
        XCTAssertEqual(
            state.double("surfaceWorldDistance") ?? .nan,
            distance,
            accuracy: 0.03,
            file: file,
            line: line
        )
        XCTAssertEqual(
            state.double("surfaceWorldElevation") ?? .nan,
            elevation,
            accuracy: 0.5,
            file: file,
            line: line
        )
        for key in [
            "surfaceLocalScaleX",
            "surfaceLocalScaleY",
            "surfaceLocalScaleZ"
        ] {
            XCTAssertEqual(
                state.double(key) ?? .nan,
                scale,
                accuracy: 0.01,
                "Docked surface scale is not uniform or does not match Screen Size.",
                file: file,
                line: line
            )
        }
        XCTAssertGreaterThan(
            state.double("surfaceForwardToUserDot") ?? -1,
            0.995,
            "Docked surface is not facing the user.",
            file: file,
            line: line
        )
        XCTAssertEqual(state.bool("surfaceAnchorMatched"), true, file: file, line: line)
        XCTAssertEqual(state.bool("surfaceRenderingReady"), true, file: file, line: line)
    }
}
