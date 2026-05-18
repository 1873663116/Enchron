import XCTest

/// Page Object 基础协议 — XrPlayer E2E 测试的元素定位和操作封装
@MainActor
protocol BaseScreen {
    var app: XCUIApplication { get }
    func waitForScreen(timeout: TimeInterval) -> Bool
}

extension BaseScreen {
    func element(id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func exists(id: String, timeout: TimeInterval = 5) -> Bool {
        element(id: id).waitForExistence(timeout: timeout)
    }

    func tapElement(id: String, timeout: TimeInterval = 5) {
        let el = element(id: id)
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "Element '\(id)' not found")
        el.tap()
    }

    /// visionOS 安全的 accessibility audit 类型
    /// 来源：Apple XCUIAccessibilityAuditType 文档，仅以下 4 类确认支持 visionOS
    static var visionOSSafeAuditTypes: XCUIAccessibilityAuditType {
        [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription]
    }
}
