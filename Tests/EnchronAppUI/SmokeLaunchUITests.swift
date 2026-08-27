import XCTest

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
