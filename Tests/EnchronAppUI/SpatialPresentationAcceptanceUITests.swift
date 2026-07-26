import Foundation
import XCTest

nonisolated final class SpatialPresentationAcceptanceUITests: XCTestCase {
    private enum AcceptanceFailure: Error {
        case unmetCondition
    }

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
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launchEnvironment["ENCHRON_AUTOPLAY_FILE"] = fixtureURL.absoluteString
        app.launch()

        let windowPlayback = app.descendants(matching: .any)["PlayerUI-window-playback"].firstMatch
        XCTAssertTrue(windowPlayback.waitForExistence(timeout: 30))
        let windowState = app.descendants(matching: .any)["PlayerUI-window-control-plane"].firstMatch
        XCTAssertTrue(windowState.waitForExistence(timeout: 10))
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(
                        format: "value CONTAINS[c] 'lifecycle=playing' AND value CONTAINS 'attached=window'"
                    ),
                    object: windowState
                )],
                timeout: 30
            ),
            .completed,
            "Real PlaybackCore media never reached playing with its renderer attached to Window. Current state: \(String(describing: windowState.value))"
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)
        captureScreen(name: "01 Window real playback")

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 10))
        XCTAssertTrue(dock.isEnabled)
        tapSemanticallyWithScreenshotFallback(dock, name: "Dock")
        let environment = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        XCTAssertTrue(environment.waitForExistence(timeout: 5))
        tapSemanticallyWithScreenshotFallback(environment, name: "Day")

        let dockedState = try waitForSpatialState(
            app,
            presentation: "docked",
            timeout: 90
        )
        let dockedSession = try sessionID(from: dockedState)
        let exitSpatial = app.descendants(matching: .any)["PlayerPanel-button-exit-spatial"].firstMatch
        try requireExistence(
            exitSpatial,
            timeout: 10,
            message: "Docked playback committed, but its Player Control Deck did not appear."
        )
        XCTAssertEqual(exitSpatial.label, "Return to Window")
        let settings = app.descendants(matching: .any)["PlayerPanel-button-expand"].firstMatch
        try requireExistence(settings, timeout: 5, message: "Docked playback settings did not appear.")
        tapSemanticallyWithScreenshotFallback(settings, name: "Advanced Settings")
        try requireExistence(
            app.descendants(matching: .any)["PlayerPanel-ScreenSize-slider"].firstMatch,
            timeout: 5,
            message: "Docked Screen Size control did not appear."
        )
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-Distance-slider"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-Elevation-slider"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        captureMotionEvidence(name: "02 Docked real playback")

        tapSemanticallyWithScreenshotFallback(exitSpatial, name: "Return to Window")
        _ = try waitForWindowState(
            app,
            timeout: 90,
            message: "Docked playback did not restore Window playback."
        )
        captureScreen(name: "03 Window after Docked")

        let format = app.descendants(matching: .any)["PlayerUI-TopAction-videoFormat"].firstMatch
        try requireExistence(
            format,
            timeout: 10,
            message: "Video Format action did not appear after returning from Docked playback."
        )
        tapSemanticallyWithScreenshotFallback(format, name: "Video Format")
        let panorama360 = app.descendants(matching: .any)["PlayerUI-VideoFormat-Projection-360°"].firstMatch
        try requireExistence(
            panorama360,
            timeout: 5,
            message: "The 360° projection option did not appear."
        )
        tapSemanticallyWithScreenshotFallback(panorama360, name: "360° projection")
        let apply = app.buttons["PlayerUI-VideoFormat-apply"]
        try requireExistence(apply, timeout: 5, message: "The video format Apply action did not appear.")
        tapSemanticallyWithScreenshotFallback(apply, name: "Apply video format")

        let panoramaState = try waitForSpatialState(
            app,
            presentation: "panorama",
            timeout: 90
        )
        XCTAssertEqual(try sessionID(from: panoramaState), dockedSession)
        try requireExistence(
            exitSpatial,
            timeout: 10,
            message: "Panorama committed, but its Player Control Deck did not appear."
        )
        XCTAssertEqual(exitSpatial.label, "Return to Window")
        XCTAssertTrue(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        captureMotionEvidence(name: "04 Panorama real playback")

        tapSemanticallyWithScreenshotFallback(exitSpatial, name: "Return to Window")
        let restoredWindowState = try waitForWindowState(
            app,
            timeout: 90,
            message: "Panorama did not restore Window playback."
        )
        let resumePanorama = app.descendants(matching: .any)["PlayerUI-TopAction-resumePanorama"].firstMatch
        try requireExistence(
            resumePanorama,
            timeout: 10,
            message: "Panorama did not restore its Window portal action."
        )
        XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-TopAction-dock"].exists)
        XCTAssertTrue(
            restoredWindowState.lowercased().contains("lifecycle=playing")
        )
        XCTAssertTrue(
            restoredWindowState.contains("attached=window")
        )
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
        presentation: String,
        timeout: TimeInterval
    ) throws -> String {
        let state = app.descendants(matching: .any)["PlayerUI-spatial-state"].firstMatch
        try requireExistence(
            state,
            timeout: timeout,
            message: "\(presentation) did not expose its spatial control plane."
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS %@ AND value CONTAINS[c] 'lifecycle=playing'",
                "presentation=\(presentation)"
            ),
            object: state
        )
        guard XCTWaiter.wait(for: [expectation], timeout: 20) == .completed else {
            XCTFail(
                "\(presentation) did not settle with real playback still playing. Current state: \(String(describing: state.value))"
            )
            throw AcceptanceFailure.unmetCondition
        }
        return try XCTUnwrap(state.value as? String)
    }

    @MainActor
    private func waitForWindowState(
        _ app: XCUIApplication,
        timeout: TimeInterval,
        message: String
    ) throws -> String {
        let state = app.descendants(matching: .any)["PlayerUI-window-control-plane"].firstMatch
        try requireExistence(state, timeout: timeout, message: message)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS 'presentation=window' AND value CONTAINS 'attached=window' AND value CONTAINS[c] 'lifecycle=playing'"
            ),
            object: state
        )
        guard XCTWaiter.wait(for: [expectation], timeout: 20) == .completed else {
            XCTFail("\(message) Current state: \(String(describing: state.value))")
            throw AcceptanceFailure.unmetCondition
        }
        return try XCTUnwrap(state.value as? String)
    }

    @MainActor
    private func requireExistence(
        _ element: XCUIElement,
        timeout: TimeInterval,
        message: String
    ) throws {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail(message)
            throw AcceptanceFailure.unmetCondition
        }
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
