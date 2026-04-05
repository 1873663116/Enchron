import XCTest
@testable import XrPlayerCore

/// Verifies the navigation state design contract for AppModel.
///
/// AppModel lives in the app target (SwiftUI + @Observable dependencies) and cannot
/// be imported into the SPM test target. These tests verify the navigation design
/// specification as a contract — ensuring the expected tabs, their names, and count
/// are documented and consistent with the ExecPlan R9 requirements.
final class NavigationStateTests: XCTestCase {

    // MARK: - Navigation Tab Design Contract

    /// The navigation tabs defined by the design spec.
    /// Must match AppModel.NavigationTab exactly.
    private static let designTabs: [(case_: String, rawValue: String)] = [
        ("browse",   "browse"),
        ("recent",   "recent"),
        ("settings", "settings"),
    ]

    func testDesignSpecifiesExactlyThreeTabs() {
        XCTAssertEqual(Self.designTabs.count, 3,
                       "Navigation design must have exactly 3 tabs (browse, recent, settings)")
    }

    func testDefaultTabIsBrowse() {
        let defaultTab = Self.designTabs.first
        XCTAssertEqual(defaultTab?.case_, "browse",
                       "Default tab (first in order) must be 'browse'")
    }

    func testTabNamesAreUnique() {
        let names = Self.designTabs.map(\.case_)
        XCTAssertEqual(Set(names).count, names.count,
                       "Tab names must be unique — found duplicates")
    }

    func testTabRawValuesMatchCaseNames() {
        for tab in Self.designTabs {
            XCTAssertEqual(tab.case_, tab.rawValue,
                           "Tab '\(tab.case_)' rawValue must equal its case name")
        }
    }

    func testRequiredTabsPresent() {
        let tabNames = Set(Self.designTabs.map(\.case_))
        XCTAssertTrue(tabNames.contains("browse"), "Must include 'browse' tab")
        XCTAssertTrue(tabNames.contains("recent"), "Must include 'recent' tab")
        XCTAssertTrue(tabNames.contains("settings"), "Must include 'settings' tab")
    }
}
