import XCTest

/// UI tests for the assembled Settings screen (CategorySidebar + SettingListGroup
/// bound to SettingsViewModel / persisted UserPreferences).
nonisolated final class SettingsUITests: XCTestCase {

    @MainActor
    func testNavigatingToSettingsAndSwitchingCategory() {
        let app = XCUIApplication()
        app.launch()

        // LNCH-03: the Settings tab in the leading navigation ornament switches
        // the main window to the Settings screen.
        let settingsTab = app.descendants(matching: .any).matching(identifier: "Navigation-Ornament-tab-settings").firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20), "Settings nav tab should exist")
        settingsTab.tap()

        let playbackGroup = app.descendants(matching: .any)["Settings-Playback-group"]
        XCTAssertTrue(playbackGroup.waitForExistence(timeout: 10),
                      "Settings should open on the Playback category")

        // SET-16: tapping a category switches the detail pane to that group.
        let diagnosticsCategory = app.descendants(matching: .any).matching(identifier: "Settings-category-diagnostics").firstMatch
        XCTAssertTrue(diagnosticsCategory.waitForExistence(timeout: 10),
                      "Diagnostics category row should exist")
        diagnosticsCategory.tap()

        let diagnosticsGroup = app.descendants(matching: .any)["Settings-Diagnostics-group"]
        XCTAssertTrue(diagnosticsGroup.waitForExistence(timeout: 10),
                      "Tapping the Diagnostics category should reveal its settings group (SET-16)")
    }
}
