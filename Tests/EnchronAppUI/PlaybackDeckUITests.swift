import XCTest

/// Simulator regression for the production Window playback controls.
nonisolated final class PlaybackDeckUITests: XCTestCase {

    @MainActor
    func testPolishedDeckIsLivePlaybackSurface() {
        let app = launchPlayer()

        let play = app.descendants(matching: .any)["PlayerPanel-button-play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20),
                      "Fused panel play button should mount as the live transport")
        XCTAssertTrue(play.label == "Play" || play.label == "Pause",
                      "Play button label should reflect live playback state, got \(play.label)")

        let more = app.descendants(matching: .any)["PlayerPanel-menu-more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5),
                      "Fused panel ⋯ menu (subtitles / audio / speed) should be present")

        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-TopAction-dock"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testTransportChangesPlaybackState() {
        let app = launchPlayer()
        let play = app.descendants(matching: .any)["PlayerPanel-button-play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        let initialLabel = play.label
        let toggledLabel = initialLabel == "Play" ? "Pause" : "Play"
        play.tap()
        XCTAssertEqual(play.label, toggledLabel)
        play.tap()
        XCTAssertEqual(play.label, initialLabel)
    }

    @MainActor
    func testWindowDeckHasCanonicalOrderAndKeepsPresentationActionsOutsideDeck() {
        let app = launchPlayer()
        let identifiers = [
            "PlayerPanel-button-expand",
            "PlayerPanel-button-rewind",
            "PlayerPanel-button-play",
            "PlayerPanel-button-forward",
            "PlayerPanel-menu-more",
        ]
        let controls = identifiers.map { app.descendants(matching: .any)[$0].firstMatch }

        XCTAssertTrue(controls[2].waitForExistence(timeout: 20))
        for (identifier, control) in zip(identifiers, controls) {
            XCTAssertTrue(control.exists, "Missing canonical playback control: \(identifier)")
        }

        let centers = controls.map { $0.frame.midX }
        XCTAssertEqual(centers, centers.sorted(), "Playback controls must appear in canonical left-to-right order.")
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-dock"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-panorama"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-TopAction-dock"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].exists)
        attachScreenshot(app, name: "Window playback canonical controls")
    }

    @MainActor
    func testWindowActionsAndDeckShareOneControlPlane() {
        let app = launchPlayer()
        let plane = app.descendants(matching: .any)["PlayerUI-window-control-plane"].firstMatch
        XCTAssertTrue(plane.waitForExistence(timeout: 20))

        for identifier in [
            "PlayerUI-InfoBar-button-back",
            "PlayerUI-TopAction-dock",
            "PlayerUI-TopAction-videoFormat",
            "PlayerPanel-button-expand",
            "PlayerPanel-menu-more",
        ] {
            XCTAssertTrue(
                plane.descendants(matching: .any)[identifier].firstMatch.exists,
                "Control must remain inside the single Window control plane: \(identifier)"
            )
        }
    }

    @MainActor
    func testWindowFormatMenuRequiresAnExplicitApply() {
        let app = launchPlayer()
        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 20))
        format.tap()

        XCTAssertTrue(app.buttons["PlayerUI-VideoFormat-apply"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-180°"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-360°"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-VideoFormat-Stereo Layout-Mono"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-Flat"].exists)

        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-window-playback"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch.exists)
    }

    @MainActor
    func testTopActionsExposeDockMenu() {
        let app = launchPlayer()

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 20))
        dock.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-DockMenu-day"]
                .waitForExistence(timeout: 5)
        )
        attachScreenshot(app, name: "Docking menu")
    }

    @MainActor
    func testDockTransitionReplacesTheWindowSurfaceWithoutCrashing() {
        let app = launchPlayer()
        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 20))
        dock.tap()

        let environment = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        environment.tap()

        let exitSpatial = app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 20))
        XCTAssertEqual(exitSpatial.label, "Return to Window")
        let settings = app.descendants(matching: .any)["PlayerPanel-button-expand"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerPanel-ScreenSize-slider"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-Distance-slider"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-Elevation-slider"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-spatial-button-stop"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testTopActionsExposeOrthogonalVideoFormatMenu() {
        let app = launchPlayer()
        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        format.tap()
        XCTAssertTrue(app.buttons["PlayerUI-VideoFormat-apply"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-Flat"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerUI-VideoFormat-Stereo Layout-Mono"].exists)
        attachScreenshot(app, name: "Video format menu")
    }

    @MainActor
    func testPanoramaTransitionReplacesTheWindowSurfaceWithoutCrashing() {
        let app = launchPlayer()
        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 20))
        format.tap()

        let panorama360 = app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-360°"].firstMatch
        XCTAssertTrue(panorama360.waitForExistence(timeout: 5))
        panorama360.tap()
        app.buttons["PlayerUI-VideoFormat-apply"].tap()

        let exitSpatial = app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 20))
        XCTAssertEqual(exitSpatial.label, "Return to Window")
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-spatial-button-stop"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func launchPlayer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] =
            "http://enchrolab:verification@127.0.0.1:18737/spatial-acceptance.mp4"
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
