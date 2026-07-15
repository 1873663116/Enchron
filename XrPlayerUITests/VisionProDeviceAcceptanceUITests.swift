import XCTest

nonisolated final class VisionProDeviceAcceptanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Final spatial presentation requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testDockAndPanoramaRoundTripsInOneLaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = "/tmp/EnchronUITest.mkv"
        app.launch()

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 20))
        dock.tap()

        let environment = app.descendants(matching: .any)["PlayerUI-DockMenu-darkTheatre"].firstMatch
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        environment.tap()

        let exitSpatial = app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 20))
        XCTAssertEqual(exitSpatial.label, "Undock")
        exitSpatial.tap()
        XCTAssertTrue(dock.waitForExistence(timeout: 20))

        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 5))
        format.tap()

        let panorama360 = app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-360°"].firstMatch
        XCTAssertTrue(panorama360.waitForExistence(timeout: 5))
        panorama360.tap()
        app.buttons["PlayerUI-VideoFormat-apply"].tap()

        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 20))
        XCTAssertEqual(exitSpatial.label, "Exit Panorama")
        exitSpatial.tap()
        XCTAssertTrue(format.waitForExistence(timeout: 20))
    }

}

nonisolated final class PhotosPlaybackDeviceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        let explicitlyEnabled = ProcessInfo.processInfo.environment["ENCHRON_RUN_PHOTOS_TEST"] == "1"
            || UserDefaults.standard.bool(forKey: "ENCHRON_RUN_PHOTOS_TEST")
        guard explicitlyEnabled else {
            throw XCTSkip("Run scripts/verify-photos-simulator.zsh to seed a Simulator Photos library.")
        }
#endif
    }

    @MainActor
    func testFreshPhotosImportStartsRealPlayback() {
        let app = XCUIApplication()
        let permissionLabels = [
            "Allow Full Access",
            "Allow Access to All Photos",
            "Continue",
            "允许完全访问",
            "允许访问所有照片",
            "继续"
        ]
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for label in permissionLabels where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            let buttons = alert.buttons
            guard buttons.count >= 2 else { return false }
            buttons.element(boundBy: buttons.count == 3 ? 1 : 0).tap()
            return true
        }
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launch()

        let existingMedia = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"))
        XCTAssertEqual(existingMedia.count, 0, "The device import test must begin with an empty media library.")

        let manage = app.buttons["Manage media library"]
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        manage.tap()
        let addPhotos = app.buttons["Add from Photos"]
        XCTAssertTrue(addPhotos.waitForExistence(timeout: 5))
        addPhotos.tap()
#if !targetEnvironment(simulator)
        Thread.sleep(forTimeInterval: 3)
        app.tap()
#endif

        let firstPhoto = app.collectionViews.cells.firstMatch
        XCTAssertTrue(
            firstPhoto.waitForExistence(timeout: 20),
            "Photos Picker did not expose a selectable video. App hierarchy: \(app.debugDescription)"
        )
        firstPhoto.tap()
        let add = app.buttons["Add"]
        let done = app.buttons["Done"]
        if add.waitForExistence(timeout: 5) {
            add.tap()
        } else {
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            done.tap()
        }

        let media = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'MediaLibrary-grid-video-'"))
            .firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 20), "Fresh Photos import did not create a media reference.")
        media.tap()

        let player = app.descendants(matching: .any)["PlayerUI-window-playback"].firstMatch
        let libraryError = app.alerts["Media Library Error"]
        XCTAssertTrue(
            player.waitForExistence(timeout: 30),
            "Real playback did not open. Media library error: \(libraryError.label)"
        )
        let playing = NSPredicate(format: "value == 'playing'")
        let ready = XCTNSPredicateExpectation(predicate: playing, object: player)
        XCTAssertEqual(
            XCTWaiter.wait(for: [ready], timeout: 30),
            .completed,
            "Playback window appeared but never reached the playing state. Current value: \(player.value)"
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)
    }
}
