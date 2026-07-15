import XCTest

/// UI tests for the virtual Media Library and external source browser.
nonisolated final class FilesBrowsingUITests: XCTestCase {

    @MainActor
    func testNavigationOrnamentHasAllTabs() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()

        for tab in ["files", "settings", "environment"] {
            let element = app.descendants(matching: .any)["Navigation-Ornament-tab-\(tab)"]
            XCTAssertTrue(element.waitForExistence(timeout: 20),
                          "Navigation ornament should expose the \(tab) tab")
        }
    }

    @MainActor
    func testSearchFiltersCatalog() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()

        let interstellar = app.descendants(matching: .any)["MediaLibrary-grid-video-Interstellar.mkv"]
        XCTAssertTrue(interstellar.waitForExistence(timeout: 20), "Catalog should render before searching")
        let matrix = app.descendants(matching: .any)["MediaLibrary-grid-video-The Matrix.mkv"]
        XCTAssertTrue(matrix.exists, "The Matrix card should be present before filtering")

        let search = app.textFields["FileBrowsing-FilesScreen-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search field should exist")
        search.tap()
        search.typeText("Matrix")

        XCTAssertTrue(matrix.waitForExistence(timeout: 10),
                      "Searching 'Matrix' should keep The Matrix card")
        XCTAssertFalse(interstellar.exists,
                       "Searching 'Matrix' should filter out non-matching films (Interstellar)")
    }

    @MainActor
    func testWebDAVSourceFormIsReachable() {
        let app = launchFiles()
        openAddSourceMenu(in: app)

        let webDAV = app.buttons["WebDAV"]
        XCTAssertTrue(webDAV.waitForExistence(timeout: 5))
        webDAV.tap()

        XCTAssertTrue(app.textFields["FileBrowsing-SourceConnection-address"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["FileBrowsing-SourceConnection-username"].exists)
        XCTAssertTrue(app.secureTextFields["FileBrowsing-SourceConnection-password"].exists)
        XCTAssertTrue(app.buttons["FileBrowsing-SourceConnection-connect"].exists)
    }

    @MainActor
    func testSMBSourceFormRequiresShare() {
        let app = launchFiles()
        openAddSourceMenu(in: app)

        let smb = app.buttons["SMB"]
        XCTAssertTrue(smb.waitForExistence(timeout: 5))
        smb.tap()

        XCTAssertTrue(app.textFields["FileBrowsing-SourceConnection-address"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["FileBrowsing-SourceConnection-share"].exists)
        XCTAssertTrue(app.switches["FileBrowsing-SourceConnection-guest"].exists)
    }

    @MainActor
    func testMediaLibraryMenuExposesReferenceSources() {
        let app = launchFiles()
        let manage = app.buttons["Manage media library"]
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        manage.tap()

        for label in [
            "Add Files",
            "Add Folder Contents",
            "Add from Photos",
            "New Library Folder"
        ] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testCreatesVirtualLibraryFolder() {
        let app = launchFiles()
        let manage = app.buttons["Manage media library"]
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        manage.tap()

        let newFolder = app.buttons["New Library Folder"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 5))
        newFolder.tap()

        // visionOS presents SwiftUI alerts as a system surface and exposes the
        // field and action by their visible labels rather than app identifiers.
        let name = app.textFields["Folder name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Series")
        app.buttons["Create"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["MediaLibrary-grid-folder-Series"].waitForExistence(timeout: 10)
        )
    }

    @MainActor
    private func launchFiles() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()
        return app
    }

    @MainActor
    private func openAddSourceMenu(in app: XCUIApplication) {
        let more = app.buttons["More source actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        more.tap()

        let add = app.buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
    }
}
