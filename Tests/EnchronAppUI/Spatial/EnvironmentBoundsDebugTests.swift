import XCTest

nonisolated final class EnvironmentBoundsDebugTests: XCTestCase {
    @MainActor
    func testCompactBounds() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.xiongzhipeng.Enchron")
        app.activate()
        let restore = app.buttons["EnvironmentHome-button-restore"].firstMatch
        if restore.exists { restore.tap() }
        let entry = app.descendants(matching: .any)["Navigation-Ornament-tab-environment"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        entry.tap()
        let minimize = app.buttons["EnvironmentHome-button-minimize"].firstMatch
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
        minimize.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "compact-window-hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "compact-window"
        shot.lifetime = .keepAlways
        add(shot)
        Thread.sleep(forTimeInterval: 20)
        restore.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 10))
    }
}
