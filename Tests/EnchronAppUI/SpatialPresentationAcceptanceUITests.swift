import Foundation
import XCTest

nonisolated final class SpatialPresentationAcceptanceUITests: XCTestCase {
    private let fixtureURL = URL(
        string: "http://enchrolab:verification@127.0.0.1:18737/spatial-acceptance.mp4"
    )!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRealPlaybackDockedAndPanoramaRoundTrips() async throws {
        try await requireFixtureServer()
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_RESET_MEDIA_LIBRARY"] = "1"
        app.launchEnvironment["ENCHRON_SPATIAL_ACCEPTANCE"] = "1"
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixtureURL.absoluteString
        app.launch()

        let windowPlayback = app.descendants(matching: .any)["PlayerUI-window-playback"].firstMatch
        XCTAssertTrue(windowPlayback.waitForExistence(timeout: 30))
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == 'playing'"),
                    object: windowPlayback
                )],
                timeout: 30
            ),
            .completed,
            "Real PlaybackCore media never reached playing in Window."
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)
        captureScreen(name: "01 Window real playback")

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        XCTAssertTrue(dock.isEnabled)
        tapSemanticallyWithScreenshotFallback(dock, name: "Dock")
        let environment = app.descendants(matching: .any)["PlayerUI-DockMenu-darkTheatre"].firstMatch
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        tapSemanticallyWithScreenshotFallback(environment, name: "Dark Theatre")

        let exitSpatial = app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch
        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 30))
        XCTAssertEqual(exitSpatial.label, "Undock")
        XCTAssertTrue(
            app.descendants(matching: .any)["PlayerPanel-ScreenSize-slider"]
                .waitForExistence(timeout: 5)
        )
        let dockedState = try waitForSpatialState(app, presentation: "docked")
        let dockedSession = try sessionID(from: dockedState)
        captureMotionEvidence(name: "02 Docked real playback")

        tapSemanticallyWithScreenshotFallback(exitSpatial, name: "Undock")
        XCTAssertTrue(windowPlayback.waitForExistence(timeout: 30), "Undock did not restore Window playback.")
        captureScreen(name: "03 Window after Docked")

        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        XCTAssertTrue(format.waitForExistence(timeout: 10))
        tapSemanticallyWithScreenshotFallback(format, name: "Video Format")
        let panorama360 = app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-360°"].firstMatch
        XCTAssertTrue(panorama360.waitForExistence(timeout: 5))
        tapSemanticallyWithScreenshotFallback(panorama360, name: "360° projection")
        let apply = app.buttons["PlayerUI-VideoFormat-apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        tapSemanticallyWithScreenshotFallback(apply, name: "Apply video format")

        XCTAssertTrue(exitSpatial.waitForExistence(timeout: 30))
        XCTAssertEqual(exitSpatial.label, "Exit Panorama")
        let panoramaState = try waitForSpatialState(app, presentation: "panorama")
        XCTAssertEqual(try sessionID(from: panoramaState), dockedSession)
        captureMotionEvidence(name: "04 Panorama real playback")

        tapSemanticallyWithScreenshotFallback(exitSpatial, name: "Exit Panorama")
        XCTAssertTrue(format.waitForExistence(timeout: 30), "Exit Panorama did not restore Window playback.")
        XCTAssertEqual(windowPlayback.value as? String, "playing")
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)
        captureScreen(name: "05 Window after Panorama")
    }

    @MainActor
    private func requireFixtureServer() async throws {
        var request = URLRequest(url: fixtureURL)
        request.timeoutInterval = 2
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(
            "Basic " + Data("enchrolab:verification".utf8).base64EncodedString(),
            forHTTPHeaderField: "Authorization"
        )
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 206 else {
                throw XCTSkip("Run Scripts/verification/verify-spatial-presentations-simulator.zsh to start the fixture server.")
            }
        } catch {
            throw XCTSkip("Spatial acceptance fixture server is unavailable: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func waitForSpatialState(
        _ app: XCUIApplication,
        presentation: String
    ) throws -> String {
        let state = app.descendants(matching: .any)["PlayerUI-spatial-control-plane"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 20))
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@ AND value CONTAINS 'lifecycle=playing'", "presentation=\(presentation)"),
            object: state
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed)
        return try XCTUnwrap(state.value as? String)
    }

    private func sessionID(from state: String) throws -> String {
        let value = state.split(separator: ";")
            .first { $0.hasPrefix("session=") }?
            .dropFirst("session=".count)
        let session = try XCTUnwrap(value.map(String.init))
        XCTAssertNotEqual(session, "none")
        XCTAssertNotEqual(session, "ui-test-fixture")
        return session
    }

    @MainActor
    private func tapSemanticallyWithScreenshotFallback(_ element: XCUIElement, name: String) {
        if element.isHittable {
            element.tap()
            return
        }
        let screenshot = XCUIScreen.main.screenshot()
        attach(screenshot, name: "Visual fallback before \(name)")
        XCTAssertFalse(
            element.frame.isEmpty || element.frame.isNull || element.frame.isInfinite,
            "\(name) has no usable semantic geometry for screenshot-coordinate fallback."
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    private func captureMotionEvidence(name: String) {
        let first = XCUIScreen.main.screenshot()
        attach(first, name: "\(name) first frame")
        Thread.sleep(forTimeInterval: 1)
        let second = XCUIScreen.main.screenshot()
        attach(second, name: "\(name) second frame")
        XCTAssertNotEqual(
            first.pngRepresentation,
            second.pngRepresentation,
            "The Simulator screen did not change while \(name) was expected to be playing."
        )
    }

    @MainActor
    private func captureScreen(name: String) {
        attach(XCUIScreen.main.screenshot(), name: name)
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
