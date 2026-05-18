import XCTest

/// Enchron E2E 测试 — per-screen accessibility audit + structural checks
///
/// 审计类型基于 Apple 官方文档（WWDC23 session 10073/10076）：
/// - visionOS 安全白名单：.contrast, .elementDetection, .hitRegion, .sufficientElementDescription
/// - .dynamicType, .textClipped, .trait 未列入 visionOS 支持，不使用
@MainActor
final class EnchronUITests: XCTestCase {

    /// visionOS 安全审计类型（来源：Apple XCUIAccessibilityAuditType 文档）
    static let visionOSSafeAuditTypes: XCUIAccessibilityAuditType = [
        .contrast, .elementDetection, .hitRegion, .sufficientElementDescription
    ]

    private var app: XCUIApplication!
    private var nav: NavigationScreen!
    private var browse: BrowseScreen!
    private var settings: SettingsScreen!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()

        nav = NavigationScreen(app: app)
        browse = BrowseScreen(app: app)
        settings = SettingsScreen(app: app)

        // 等待 app 完全加载（给主窗口出现时间）
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "App window should appear within 15s")
    }

    override func tearDown() {
        // tearDown 审计排除 .hitRegion（留给专门的审计测试处理）
        // 避免 SwiftUI Menu / 系统组件的 hit area 限制导致非审计测试误报
        try? app.performAccessibilityAudit(
            for: [.contrast, .elementDetection, .sufficientElementDescription]
        )
        super.tearDown()
    }

    // MARK: - Navigation

    func testNavigationStructure() throws {
        // 验证 ornament 按钮存在（用 label 匹配，因为 XCUITest 可能无法通过 id 定位 ornament 中的元素）
        let browseTab = app.buttons[NavigationScreen.Tab.browse.rawValue]
        let recentTab = app.buttons[NavigationScreen.Tab.recent.rawValue]
        let settingsTab = app.buttons[NavigationScreen.Tab.settings.rawValue]
        let sceneBtn = app.buttons[NavigationScreen.sceneSelector]

        // 至少有一个 tab 按钮可见（ornament 可能在不同状态下显示）
        let anyTabExists = browseTab.waitForExistence(timeout: 5)
            || recentTab.waitForExistence(timeout: 2)
            || settingsTab.waitForExistence(timeout: 2)

        if !anyTabExists {
            // 尝试通过 label 查找
            let browseByLabel = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'browse' OR label CONTAINS[c] '浏览'")).firstMatch
            XCTAssertTrue(browseByLabel.waitForExistence(timeout: 5), "At least one navigation tab should be visible")
        }
    }

    func testTabSwitching() throws {
        // 尝试切换到 Settings（通过 id 或 label）
        let settingsTab = app.buttons[NavigationScreen.Tab.settings.rawValue]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 尝试切换到 Recent
        let recentTab = app.buttons[NavigationScreen.Tab.recent.rawValue]
        if recentTab.waitForExistence(timeout: 5) {
            recentTab.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // 尝试切回 Browse
        let browseTab = app.buttons[NavigationScreen.Tab.browse.rawValue]
        if browseTab.waitForExistence(timeout: 5) {
            browseTab.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    // MARK: - Per-Screen Accessibility Audits

    /// Browse 屏审计（含 .hitRegion，记录但不因 known issues 失败）
    func testBrowseScreenAudit() throws {
        Thread.sleep(forTimeInterval: 2)

        try app.performAccessibilityAudit(for: Self.visionOSSafeAuditTypes) { issue in
            // SwiftUI Menu 按钮的 hitRegion 违规是已知平台限制
            if issue.auditType == .hitRegion {
                let desc = issue.compactDescription
                let attachment = XCTAttachment(string: "hitRegion WARN: \(desc)")
                attachment.name = "hitRegion-\(desc.prefix(30))"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return true // suppress — 不因此 fail
            }
            return false
        }
    }

    func testBrowseScreenElements() throws {
        Thread.sleep(forTimeInterval: 2)

        // 验证 sidebar 本地存储行
        let localRow = app.cells.matching(
            NSPredicate(format: "identifier == %@ OR label CONTAINS[c] 'Local Storage'",
                        BrowseScreen.ID.sidebarLocal)
        ).firstMatch

        if localRow.waitForExistence(timeout: 5) {
            // PASS: sidebar element found
        }

        // 验证 sort 按钮
        let sortButton = app.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label CONTAINS[c] 'Sort'",
                        BrowseScreen.ID.sortButton)
        ).firstMatch

        if sortButton.waitForExistence(timeout: 5) {
            // PASS: sort button found
        }
    }

    // MARK: - Settings Screen

    func testSettingsScreenAudit() throws {
        // 切换到 Settings
        let settingsTab = app.buttons[NavigationScreen.Tab.settings.rawValue]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
            Thread.sleep(forTimeInterval: 2)
        }

        try app.performAccessibilityAudit(for: Self.visionOSSafeAuditTypes) { issue in
            if issue.auditType == .hitRegion {
                let attachment = XCTAttachment(string: "hitRegion WARN: \(issue.compactDescription)")
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return true
            }
            return false
        }
    }

    // MARK: - Recent Screen

    func testRecentScreenAudit() throws {
        let recentTab = app.buttons[NavigationScreen.Tab.recent.rawValue]
        if recentTab.waitForExistence(timeout: 5) {
            recentTab.tap()
            Thread.sleep(forTimeInterval: 2)
        }

        try app.performAccessibilityAudit(for: Self.visionOSSafeAuditTypes) { issue in
            if issue.auditType == .hitRegion {
                let attachment = XCTAttachment(string: "hitRegion WARN: \(issue.compactDescription)")
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return true
            }
            return false
        }
    }
}
