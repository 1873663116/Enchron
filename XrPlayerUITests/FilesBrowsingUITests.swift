import XCTest

/// UI tests for main-window Files browsing against the live FakeApp process.
///
/// NOTE on identifiers (discovered via XCUITest tree dump 2026-06-19): the
/// `FilesScreen` toolbar controls (search / sort / view-mode / back-forward) all
/// surface with the *parent* identifier `FileBrowsing-FilesScreen-contentArea`
/// instead of their own — the contentArea identifier clobbers the per-control
/// anchors the ledger specifies. Until that app a11y bug is fixed, this suite
/// queries those controls by element type / label rather than by their intended
/// identifier. Grid card identifiers are NOT clobbered and are used directly.
nonisolated final class FilesBrowsingUITests: XCTestCase {

    @MainActor
    func testNavigationOrnamentHasAllTabs() {
        let app = XCUIApplication()
        app.launch()

        // LNCH-01: the leading navigation ornament exposes the three destinations.
        for tab in ["files", "settings", "environment"] {
            let element = app.descendants(matching: .any)["Navigation-Ornament-tab-\(tab)"]
            XCTAssertTrue(element.waitForExistence(timeout: 20),
                          "Navigation ornament should expose the \(tab) tab")
        }
    }

    @MainActor
    func testSearchFiltersCatalog() {
        let app = XCUIApplication()
        app.launch()

        let interstellar = app.descendants(matching: .any)["FileBrowsing-grid-video-Interstellar.mkv"]
        XCTAssertTrue(interstellar.waitForExistence(timeout: 20), "Catalog should render before searching")
        let matrix = app.descendants(matching: .any)["FileBrowsing-grid-video-The Matrix.mkv"]
        XCTAssertTrue(matrix.exists, "The Matrix card should be present before filtering")

        // UC-FILE-33: typing in the search field filters the grid by name. The
        // search field's own identifier is clobbered (see class note), so query
        // it as the screen's single TextField.
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field should exist")
        search.tap()
        search.typeText("Matrix")

        XCTAssertTrue(matrix.waitForExistence(timeout: 10),
                      "Searching 'Matrix' should keep The Matrix card")
        XCTAssertFalse(interstellar.exists,
                       "Searching 'Matrix' should filter out non-matching films (Interstellar)")
    }
}
