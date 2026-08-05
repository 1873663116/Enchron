import XCTest

/// Smoke test for the launched Enchron main window.
///
/// Proves the scheme runs real UI tests against the actual app process: it
/// launches Enchron and asserts the main window reaches the foreground and
/// renders interactive controls. Replaces the previously empty UI-test target
/// whose passing result asserted nothing.
///
/// `nonisolated` opts this test class out of the project-wide default
/// `MainActor` isolation so its inherited `XCTestCase` initializers stay
/// nonisolated; the test method opts back into `@MainActor` for the
/// `XCUIApplication` API.
nonisolated final class SmokeLaunchUITests: XCTestCase {

    @MainActor
    func testAppLaunchesToInteractiveMainWindow() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()

        XCTAssertEqual(app.state, .runningForeground,
                       "App should reach the foreground after launch")

        let filesScreen = app.descendants(matching: .any)[
            "FileBrowsing-FilesScreen"
        ].firstMatch
        let filesTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-files"
        ].firstMatch
        let filesScreenAppeared = filesScreen.waitForExistence(timeout: 20)
        let filesTabAppeared = filesTab.waitForExistence(timeout: 5)
        attachScreenshot(from: app, name: "smoke-launch-main-window")

        XCTAssertTrue(
            filesScreenAppeared,
            "Main window should open to the Media Library surface."
        )
        XCTAssertTrue(
            filesTabAppeared && filesTab.isEnabled && filesTab.isHittable,
            "The Files tab should be available through the public interface."
        )
    }

    @MainActor
    func testSpatialRegressionLaunchesBeforeMediaSelection() throws {
        let identifier = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 1
        )[0]
        let app = launchSpatialRegressionApp()

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "The spatial-regression app must reach the foreground before media selection."
        )

        let initialState = try XCTUnwrap(waitForState(
            in: app,
            identifier: "PlayerUI-application-state",
            timeout: 30
        ) {
            $0.string("active") == "false"
                && $0.string("presentation") == "window"
                && $0.string("transition") == "none"
                && $0.string("pendingSpatialEffect") == "none"
                && $0.string("immersiveSpaceResidency") == "closed"
                && $0.string("environmentCardResidency") == "closed"
                && $0.string("environment") == "none"
                && $0.string("environmentEffect") == "none"
        })
        attachState(initialState, name: "spatial-regression-launch-state")

        guard let card = waitForHittableRegisteredMediaCard(
            identifier: identifier,
            in: app,
            timeout: 30
        ) else {
            attachScreenshot(
                from: app,
                name: "spatial-regression-media-selection-not-ready"
            )
            XCTFail(
                "Registered media must be available before the spatial handoff begins."
            )
            return
        }
        attachScreenshot(from: app, name: "spatial-regression-media-selection-ready")
        XCTAssertTrue(card.isHittable)
    }
}
