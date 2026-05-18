import XCTest

/// 文件浏览界面 — sidebar + content grid
@MainActor
struct BrowseScreen: BaseScreen {
    let app: XCUIApplication

    enum ID {
        static let sidebarLocal = "FileBrowsing-Sidebar-row-local"
        static let sortButton = "FileBrowsing-Toolbar-button-sort"
        static let contentSkeleton = "FileBrowsing-ContentGrid-skeleton"

        static func videoCard(_ id: String) -> String {
            "FileBrowsing-VideoCard-button-\(id)"
        }
        static func folder(_ id: String) -> String {
            "FileBrowsing-ContentGrid-button-folder-\(id)"
        }
        static func filter(_ name: String) -> String {
            "FileBrowsing-Filter-button-\(name)"
        }
        static func sidebarRow(_ id: String) -> String {
            "FileBrowsing-Sidebar-row-\(id)"
        }
    }

    func waitForScreen(timeout: TimeInterval = 10) -> Bool {
        exists(id: ID.sidebarLocal, timeout: timeout)
    }

    var localStorageRow: XCUIElement { element(id: ID.sidebarLocal) }
    var sortButton: XCUIElement { element(id: ID.sortButton) }

    /// 当前可见的 video card 数量
    var visibleVideoCards: Int {
        app.buttons.allElementsBoundByIndex.filter {
            $0.identifier.hasPrefix("FileBrowsing-VideoCard-button-")
        }.count
    }
}
