import XCTest

/// NavigationOrnament — 左侧导航胶囊（3 tab + scene selector）
@MainActor
struct NavigationScreen: BaseScreen {
    let app: XCUIApplication

    enum Tab: String {
        case browse = "Navigation-Ornament-tab-browse"
        case recent = "Navigation-Ornament-tab-recent"
        case settings = "Navigation-Ornament-tab-settings"
    }

    static let sceneSelector = "Navigation-Ornament-button-sceneSelector"

    func waitForScreen(timeout: TimeInterval = 10) -> Bool {
        exists(id: Tab.browse.rawValue, timeout: timeout)
    }

    func switchTo(_ tab: Tab) {
        tapElement(id: tab.rawValue)
    }

    var sceneSelectorButton: XCUIElement {
        element(id: Self.sceneSelector)
    }
}
