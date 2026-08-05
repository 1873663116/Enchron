import XCTest

/// Vision Pro regression for the production Window playback controls.
nonisolated final class PlaybackDeckUITests: XCTestCase {

    @MainActor
    func testPolishedDeckIsLivePlaybackSurface() {
        let app = launchPlayer()

        let play = app.descendants(matching: .any)["PlayerPanel-button-play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20),
                      "Fused panel play button should mount as the live transport")
        XCTAssertTrue(play.label == "Play" || play.label == "Pause",
                      "Play button label should reflect live playback state, got \(play.label)")

        let more = app.descendants(matching: .any)["PlayerUI-TopAction-more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5),
                      "Window chrome More menu should be present")

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
    func testWindowDeckKeepsTransportAndPresentationActionsSeparated() {
        let app = launchPlayer()
        let identifiers = [
            "PlayerPanel-button-rewind",
            "PlayerPanel-button-play",
            "PlayerPanel-button-forward",
        ]
        let controls = identifiers.map { app.descendants(matching: .any)[$0].firstMatch }

        XCTAssertTrue(controls[1].waitForExistence(timeout: 20))
        for (identifier, control) in zip(identifiers, controls) {
            XCTAssertTrue(control.exists, "Missing canonical playback control: \(identifier)")
        }

        let centers = controls.map { $0.frame.midX }
        XCTAssertEqual(centers, centers.sorted(), "Playback controls must appear in canonical left-to-right order.")
        let mediaInformation = app.descendants(matching: .any)["PlayerPanel-media-information"].firstMatch
        let progress = app.descendants(matching: .any)["PlayerPanel-progress"].firstMatch
        XCTAssertTrue(mediaInformation.exists)
        XCTAssertTrue(progress.exists)
        XCTAssertLessThan(controls[2].frame.maxX, mediaInformation.frame.minX)
        XCTAssertLessThan(mediaInformation.frame.maxY, progress.frame.midY)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-window-media-overlay"].exists)
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
            "PlayerPanel-button-play",
            "PlayerUI-TopAction-more",
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
        let app = launchPlayerForDeviceFixture()

        let windowPlayback = app.descendants(matching: .any)["PlayerUI-window-playback"].firstMatch
        XCTAssertTrue(windowPlayback.waitForExistence(timeout: 30))
        let failure = app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].firstMatch
        if failure.waitForExistence(timeout: 2) {
            attachScreenshot(app, name: "dock-menu-playback-load-failure")
            XCTFail(
                "Autoplay failed before Dock chrome appeared. Playback value: \(String(describing: windowPlayback.value))"
            )
            return
        }

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 30))
        attachScreenshot(app, name: "dock-menu-before-open")
        dock.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-DockMenu-day"]
                .waitForExistence(timeout: 5)
        )
        attachScreenshot(app, name: "dock-system-menu-open")
    }

    @MainActor
    func testWindowMoreMakesExternalSubtitleSelectionReachable() {
        let app = launchPlayer()
        let more = app.descendants(matching: .any)["PlayerUI-TopAction-more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()

        let subtitles = app.descendants(matching: .any)["PlayerUI-menu-subtitles"].firstMatch
        XCTAssertTrue(
            subtitles.waitForExistence(timeout: 5),
            "Window More must expose Subtitles even when Off is the only current track choice."
        )
        subtitles.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerUI-menu-subtitle-chooseFile"]
                .waitForExistence(timeout: 5),
            "Window Subtitles must expose the real file importer action."
        )
        attachScreenshot(app, name: "Window external subtitle action")
    }

    @MainActor
    func testSpatialMoreMakesExternalSubtitleSelectionReachable() {
        let app = launchPlayer()
        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 20))
        dock.tap()
        let environment = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        environment.tap()

        let more = app.descendants(matching: .any)["PlayerPanel-menu-more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()
        let subtitles = app.descendants(matching: .any)["PlayerPanel-menu-subtitles"].firstMatch
        XCTAssertTrue(subtitles.waitForExistence(timeout: 5))
        subtitles.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerPanel-menu-subtitle-chooseFile"]
                .waitForExistence(timeout: 5),
            "Docked and Panorama Subtitles must expose the real file importer action."
        )
        attachScreenshot(app, name: "Spatial external subtitle action")
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
        let settings = app.descendants(matching: .any)["PlayerPanel-button-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let more = app.descendants(matching: .any)["PlayerPanel-menu-more"].firstMatch
        let mediaInformation = app.descendants(matching: .any)["PlayerPanel-media-information"].firstMatch
        XCTAssertTrue(more.exists)
        XCTAssertTrue(mediaInformation.exists)

        more.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerPanel-menu-subtitles"]
                .waitForExistence(timeout: 5),
            "Docked More must expose the same subtitle selection as Window playback."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerPanel-menu-audio"]
                .waitForExistence(timeout: 5),
            "Docked More must expose the same audio-track selection as Window playback."
        )
        more.tap()

        let play = app.descendants(matching: .any)["PlayerPanel-button-play"].firstMatch
        XCTAssertEqual(
            play.frame.midX,
            mediaInformation.frame.midX,
            accuracy: 2,
            "The transport group must keep Play on the spatial deck centerline."
        )
        XCTAssertLessThan(settings.frame.midX, exitSpatial.frame.midX)
        XCTAssertLessThan(exitSpatial.frame.midX, play.frame.midX)
        XCTAssertLessThan(play.frame.midX, more.frame.midX)
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
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-button-settings"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-menu-tracks"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-spatial-button-stop"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func launchPlayer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        let fixture =
            ProcessInfo.processInfo.environment["ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL"]
            ?? "http://enchrolab:verification@127.0.0.1:18737/spatial-acceptance.mp4"
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture
        app.launch()
        return app
    }

    /// Device-local file autoplay. Avoids `ENCHRON_UI_TESTING` so the app adds the
    /// file through Media Library instead of asking FFmpeg to open a raw path that
    /// UI-testing autoplay may not resolve inside the sandboxed container.
    @MainActor
    private func launchPlayerForDeviceFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        let fixture = ProcessInfo.processInfo.environment[
            "ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL"
        ]
        XCTAssertNotNil(
            fixture,
            "Set ENCHRON_DEVICE_ACCEPTANCE_FIXTURE_URL to an on-device file URL."
        )
        if let fixture {
            app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixture
        }
        app.launch()
        return app
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let shots = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".cursor/acceptance-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: shots,
            withIntermediateDirectories: true
        )
        let slug = name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let url = shots.appendingPathComponent("\(slug)-screen.png")
        try? screenshot.pngRepresentation.write(to: url)
    }
}
