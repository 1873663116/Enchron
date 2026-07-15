import XCTest

/// Smoke test for the launched XrPlayer main window.
///
/// Proves the scheme runs real UI tests against the actual app process: it
/// launches XrPlayer and asserts the main window reaches the foreground and
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

        let firstControl = app.buttons.firstMatch
        XCTAssertTrue(firstControl.waitForExistence(timeout: 20),
                      "Main window should present at least one interactive control")
    }
}
