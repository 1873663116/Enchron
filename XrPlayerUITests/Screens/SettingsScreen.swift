import XCTest

/// 设置界面
@MainActor
struct SettingsScreen: BaseScreen {
    let app: XCUIApplication

    func waitForScreen(timeout: TimeInterval = 10) -> Bool {
        // Settings 页面通过 "Settings" 标题或 picker 元素判断
        app.staticTexts["Settings"].waitForExistence(timeout: timeout)
            || app.staticTexts["设置"].waitForExistence(timeout: timeout)
    }
}
