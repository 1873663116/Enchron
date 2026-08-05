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
}
