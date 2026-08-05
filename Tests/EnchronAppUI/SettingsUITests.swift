import XCTest

nonisolated final class SettingsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
#if targetEnvironment(simulator)
        throw XCTSkip("Settings visual regression requires a physical Apple Vision Pro.")
#endif
    }

    @MainActor
    func testSettingsCategoryNavigationAndVisualComposition() {
        let app = launchVisionProRegressionApp()
        let settingsTab = app.descendants(matching: .any)[
            "Navigation-Ornament-tab-settings"
        ].firstMatch
        guard requireHittable(settingsTab, named: "Settings", timeout: 20) else {
            return
        }
        settingsTab.tap()

        let screen = app.descendants(matching: .any)["Settings-SettingsScreen"].firstMatch
        let detail = app.descendants(matching: .any)[
            "Settings-SettingsScreen-detail"
        ].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 15))
        XCTAssertTrue(detail.waitForExistence(timeout: 10))

        let categories = [
            (
                id: "playback",
                group: "Settings-Playback-group",
                screenshot: "settings-01-playback"
            ),
            (
                id: "storagePrivacy",
                group: "Settings-StoragePrivacy-group",
                screenshot: "settings-02-storage-privacy"
            ),
            (
                id: "about",
                group: "Settings-About-group",
                screenshot: "settings-03-about"
            )
        ]

        for category in categories {
            let row = app.descendants(matching: .any)[
                "Settings-category-\(category.id)"
            ].firstMatch
            guard row.waitForExistence(timeout: 10), row.isEnabled else {
                XCTFail("Settings category \(category.id) did not become available.")
                continue
            }
            if row.isSelected == false {
                row.tap()
            }
            let group = app.descendants(matching: .any)[category.group].firstMatch
            XCTAssertTrue(
                group.waitForExistence(timeout: 10),
                "Selecting \(category.id) must show \(category.group)."
            )
            XCTAssertTrue(row.isSelected)
            for other in categories where other.id != category.id {
                let otherRow = app.descendants(matching: .any)[
                    "Settings-category-\(other.id)"
                ].firstMatch
                XCTAssertFalse(
                    otherRow.isSelected,
                    "Only one Settings category may be selected."
                )
            }
            XCTAssertGreaterThan(group.frame.width, 0)
            XCTAssertGreaterThan(group.frame.height, 0)
            XCTAssertTrue(detail.frame.contains(group.frame))
            attachScreenshot(from: app, name: category.screenshot)
        }

        let playback = app.descendants(matching: .any)[
            "Settings-category-playback"
        ].firstMatch
        playback.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["Settings-Playback-group"]
                .firstMatch.waitForExistence(timeout: 10)
        )
        XCTAssertTrue(playback.isSelected)
        attachHumanReviewBoundary(
            "Review the category contact sheet and clear frames for clipping, unreadable text, unexpected spacing, or visually incorrect system glass despite valid frames.",
            name: "settings-visual-human-review-boundary"
        )
    }
}
