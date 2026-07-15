import XCTest

/// UI tests for the assembled Settings screen (CategorySidebar + SettingListGroup
/// bound to SettingsViewModel / persisted UserPreferences).
nonisolated final class SettingsUITests: XCTestCase {

    @MainActor
    func testNavigatingToSettingsAndSwitchingCategory() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()

        // LNCH-03: the Settings tab in the leading navigation ornament switches
        // the main window to the Settings screen.
        let settingsTab = app.descendants(matching: .any).matching(identifier: "Navigation-Ornament-tab-settings").firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 20), "Settings nav tab should exist")
        settingsTab.tap()

        let playbackGroup = app.descendants(matching: .any)["Settings-Playback-group"]
        XCTAssertTrue(playbackGroup.waitForExistence(timeout: 10),
                      "Settings should open on the Playback category")

        let storageCategory = app.descendants(matching: .any).matching(identifier: "Settings-category-storagePrivacy").firstMatch
        XCTAssertTrue(storageCategory.waitForExistence(timeout: 10),
                      "Storage & Privacy category row should exist")
        storageCategory.tap()

        let storageGroup = app.descendants(matching: .any)["Settings-StoragePrivacy-group"]
        XCTAssertTrue(storageGroup.waitForExistence(timeout: 10),
                      "Tapping Storage & Privacy should reveal its settings group")
    }
}
