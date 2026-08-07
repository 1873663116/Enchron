import XCTest

nonisolated final class MediaLibraryRegressionUITests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Media Library visual regression requires a physical Apple Vision Pro.")
        #endif
        continueAfterFailure = true
    }

    @MainActor
    func testSingleItemGridGeometryAndVisualComposition() {
        let app = launchLibrary(dataset: "singleItem")
        let card = requireCard("MediaLibrary-grid-video-Only Film.mkv", in: app)

        XCTAssertEqual(card.frame.width, 224, accuracy: 4)
        attachScreenshot(from: app, name: "media-library-grid-single-item")
        attachHumanReviewBoundary(
            "Confirm the single card keeps the production card width and the surrounding empty space remains visually intentional.",
            name: "media-library-grid-single-item-human-review"
        )
    }

    @MainActor
    func testSparseMixedGridGeometryAndVisualComposition() {
        let app = launchLibrary(dataset: "sparseMixed")
        let cards = [
            requireCard("MediaLibrary-grid-folder-Series", in: app),
            requireCard("MediaLibrary-grid-video-Documentary.mov", in: app),
            requireCard("MediaLibrary-grid-video-Short Film.mp4", in: app)
        ]

        assertStableGridGeometry(cards)
        attachScreenshot(from: app, name: "media-library-grid-sparse-mixed")
        attachHumanReviewBoundary(
            "Confirm the folder and media cards form one coherent sparse grid without visual stretching, collision, or unintended custom chrome.",
            name: "media-library-grid-sparse-human-review"
        )
    }

    @MainActor
    func testLargeMixedGridGeometryScrollingAndVisualComposition() {
        let app = launchLibrary(dataset: "largeMixed")
        let firstIdentifiers = [
            "MediaLibrary-grid-folder-Archive",
            "MediaLibrary-grid-folder-Series",
            "MediaLibrary-grid-folder-A Very Long Library Folder Name That Must Not Change Card Geometry",
            "MediaLibrary-grid-video-Collection Item 01.mkv",
            "MediaLibrary-grid-video-Collection Item 02.mkv",
            "MediaLibrary-grid-video-Collection Item 03.mkv",
            "MediaLibrary-grid-video-Collection Item 04.mkv",
            "MediaLibrary-grid-video-Collection Item 05.mkv"
        ]
        let firstCards = firstIdentifiers.map { requireCard($0, in: app) }

        assertStableGridGeometry(firstCards)
        XCTAssertEqual(
            app.descendants(matching: .any)["FileBrowsing-FilesScreen-itemCount"]
                .firstMatch.label,
            "21 items"
        )
        let firstFrameBeforeScroll = firstCards[0].frame
        attachScreenshot(from: app, name: "media-library-grid-large-top")

        let lastCard = requireCardWhileScrolling(
            "MediaLibrary-grid-video-Collection Item 18.mkv",
            in: app
        )
        XCTAssertFalse(lastCard.frame.isEmpty)
        XCTAssertNotEqual(firstCards[0].frame.origin.y, firstFrameBeforeScroll.origin.y)
        attachScreenshot(from: app, name: "media-library-grid-large-after-scroll")
        attachHumanReviewBoundary(
            "Review the complete recording and multi-frame summary for row stability while scrolling, then inspect both clear frames for long-title truncation and visual alignment.",
            name: "media-library-grid-large-human-review"
        )
    }

    @MainActor
    func testCurrentLevelSearchUsesVisibleNamesAndRestoresTheGrid() {
        let app = launchLibrary(dataset: "hierarchical")
        let matrix = requireCard("MediaLibrary-grid-video-The Matrix.mkv", in: app)
        let arrival = requireCard("MediaLibrary-grid-video-Arrival.mkv", in: app)
        let series = requireCard("MediaLibrary-grid-folder-Series", in: app)
        XCTAssertFalse(app.descendants(matching: .any)[
            "MediaLibrary-grid-video-Hidden Matrix Cut.mkv"
        ].exists)

        let search = app.textFields["FileBrowsing-FilesScreen-search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("  mAtRiX  ")

        XCTAssertTrue(matrix.waitForExistence(timeout: 10))
        XCTAssertFalse(arrival.exists)
        XCTAssertFalse(series.exists)
        attachScreenshot(from: app, name: "media-library-search-filtered")

        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        XCTAssertTrue(arrival.waitForExistence(timeout: 10))
        XCTAssertTrue(series.waitForExistence(timeout: 10))
        attachScreenshot(from: app, name: "media-library-search-restored")
        attachHumanReviewBoundary(
            "Review the recording summary and clear frames to confirm filtering changes the current Grid cleanly and clearing the query restores the same layout.",
            name: "media-library-search-human-review"
        )
    }

    @MainActor
    func testLibraryFolderBreadcrumbBackAndForwardRestoreLocations() {
        let app = launchLibrary(dataset: "hierarchical")
        let back = app.buttons[
            "FileBrowsing-FilesScreen-navBackForward-back"
        ].firstMatch
        let forward = app.buttons[
            "FileBrowsing-FilesScreen-navBackForward-forward"
        ].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(forward.waitForExistence(timeout: 10))
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)

        requireCard("MediaLibrary-grid-folder-Series", in: app).tap()
        requireCard("MediaLibrary-grid-folder-Season 1", in: app).tap()
        XCTAssertTrue(requireCard("MediaLibrary-grid-video-Episode 01.mkv", in: app).exists)
        assertBreadcrumb("Season 1", in: app)
        XCTAssertTrue(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)

        back.tap()
        XCTAssertTrue(requireCard("MediaLibrary-grid-folder-Season 1", in: app).exists)
        assertBreadcrumb("Series", in: app)
        XCTAssertTrue(back.isEnabled)
        XCTAssertTrue(forward.isEnabled)

        forward.tap()
        XCTAssertTrue(requireCard("MediaLibrary-grid-video-Episode 01.mkv", in: app).exists)
        assertBreadcrumb("Season 1", in: app)
        XCTAssertTrue(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)

        let breadcrumb = app.descendants(matching: .any)[
            "MediaLibrary-Breadcrumb-current"
        ].firstMatch
        breadcrumb.tap()
        let ancestor = app.descendants(matching: .any)["Media Library / Series"].firstMatch
        XCTAssertTrue(ancestor.waitForExistence(timeout: 5))
        ancestor.tap()
        XCTAssertTrue(requireCard("MediaLibrary-grid-folder-Season 1", in: app).exists)
        assertBreadcrumb("Series", in: app)
        attachScreenshot(from: app, name: "media-library-folder-navigation")
        attachHumanReviewBoundary(
            "Confirm the recording shows location changes without card identity duplication, layout jumps, or content from a different hierarchy level.",
            name: "media-library-folder-navigation-human-review"
        )
    }

    @MainActor
    func testLibraryFolderCreationDuplicateRejectionMoveRenameAndRemoval() {
        let app = launchLibrary(dataset: "hierarchical")
        guard createFolder(named: "  Watch Later  ", in: app) else { return }
        var folder = requireCard("MediaLibrary-grid-folder-Watch Later", in: app)

        guard createFolder(named: " series ", in: app) else { return }
        let duplicateMessage = app.staticTexts[
            "A library folder with this name already exists here."
        ].firstMatch
        XCTAssertTrue(duplicateMessage.waitForExistence(timeout: 10))
        app.buttons["OK"].firstMatch.tap()

        let matrix = requireCard("MediaLibrary-grid-video-The Matrix.mkv", in: app)
        matrix.press(forDuration: 1.2)
        app.buttons["Move to"].firstMatch.tap()
        app.buttons["Watch Later"].firstMatch.tap()
        folder.tap()
        XCTAssertTrue(requireCard("MediaLibrary-grid-video-The Matrix.mkv", in: app).exists)

        let back = app.buttons[
            "FileBrowsing-FilesScreen-navBackForward-back"
        ].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isEnabled)
        back.tap()
        folder = requireCard("MediaLibrary-grid-folder-Watch Later", in: app)
        folder.press(forDuration: 1.2)
        app.buttons["Rename"].firstMatch.tap()
        guard let renameField = systemAlertTextField(
            identifier: "MediaLibrary-RenameFolder-name",
            placeholder: "Folder name",
            in: app
        ) else { return }
        guard let rename = systemAlertButton(
            identifier: "MediaLibrary-RenameFolder-confirm",
            label: "Rename",
            in: app
        ) else { return }
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            cancel.frame.midX,
            rename.frame.midX,
            "Cancel must appear before the primary Rename action."
        )
        renameField.tap()
        renameField.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40)
        )
        renameField.typeText("Queue")
        rename.tap()

        let renamedFolder = requireCard("MediaLibrary-grid-folder-Queue", in: app)
        renamedFolder.press(forDuration: 1.2)
        app.buttons["Remove from Library"].firstMatch.tap()
        app.buttons["Remove from Library"].firstMatch.tap()
        XCTAssertFalse(renamedFolder.waitForExistence(timeout: 3))
        attachScreenshot(from: app, name: "media-library-folder-management-complete")
        attachHumanReviewBoundary(
            "Confirm folder management uses the normal Library interface, errors remain recoverable, and removing the virtual folder does not imply deleting original media.",
            name: "media-library-folder-management-human-review"
        )
    }

    @MainActor
    func testMultipleSelectionMovesAndRemovesOnlySelectedLibraryReferences() {
        let app = launchLibrary(dataset: "hierarchical")
        let matrix = requireCard("MediaLibrary-grid-video-The Matrix.mkv", in: app)
        let arrival = requireCard("MediaLibrary-grid-video-Arrival.mkv", in: app)

        beginMultipleSelection(in: app)
        matrix.tap()
        arrival.tap()
        XCTAssertEqual(matrix.value as? String, "Selected")
        XCTAssertEqual(arrival.value as? String, "Selected")
        XCTAssertEqual(
            app.descendants(matching: .any)["MediaLibrary-MultiSelect-count"]
                .firstMatch.label,
            "2 selected"
        )
        attachScreenshot(from: app, name: "media-library-multi-select-selected-grid")

        app.descendants(matching: .any)["MediaLibrary-MultiSelect-move"].firstMatch.tap()
        app.buttons["Archive"].firstMatch.tap()
        XCTAssertFalse(matrix.waitForExistence(timeout: 3))
        XCTAssertFalse(arrival.exists)

        requireCard("MediaLibrary-grid-folder-Archive", in: app).tap()
        let movedMatrix = requireCard("MediaLibrary-grid-video-The Matrix.mkv", in: app)
        let movedArrival = requireCard("MediaLibrary-grid-video-Arrival.mkv", in: app)
        beginMultipleSelection(in: app)
        movedMatrix.tap()
        movedArrival.tap()
        app.descendants(matching: .any)["MediaLibrary-MultiSelect-delete"].firstMatch.tap()
        app.descendants(matching: .any)["MediaLibrary-MultiSelect-confirmDelete"].firstMatch.tap()

        XCTAssertFalse(movedMatrix.waitForExistence(timeout: 3))
        XCTAssertFalse(movedArrival.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["FileBrowsing-FilesScreen-emptyState"]
                .firstMatch.waitForExistence(timeout: 5)
        )
        attachScreenshot(from: app, name: "media-library-multi-select-complete")
        attachHumanReviewBoundary(
            "Confirm selection checkmarks, selected count, Move To, Delete, and Done form one clear management mode without changing the established single-item cards or context menus.",
            name: "media-library-multi-select-human-review"
        )
    }

    @MainActor
    private func launchLibrary(dataset: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launchEnvironment["ENCHRON_UI_TEST_LIBRARY_DATASET"] = dataset
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["FileBrowsing-FilesScreen"]
                .firstMatch.waitForExistence(timeout: 20)
        )
        return app
    }

    @MainActor
    private func beginMultipleSelection(in app: XCUIApplication) {
        let manage = app.descendants(matching: .any)["FileBrowsing-Manage-button"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.tap()
        let selectMultiple = app.buttons["Select Multiple"].firstMatch
        XCTAssertTrue(selectMultiple.waitForExistence(timeout: 5))
        selectMultiple.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["MediaLibrary-MultiSelect-count"]
                .firstMatch.waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func requireCard(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let card = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Missing card: \(identifier)")
        return card
    }

    @MainActor
    private func requireCardWhileScrolling(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let card = app.descendants(matching: .any)[identifier].firstMatch
        guard let scrollView = largestMediaLibraryScrollView(in: app) else {
            XCTFail("The Media Library did not expose its content scroll view.")
            return card
        }
        for _ in 0..<8 {
            if card.exists, card.isHittable {
                return card
            }
            scrollView.swipeUp()
        }
        XCTAssertTrue(
            card.waitForExistence(timeout: 5),
            "Missing card after scrolling: \(identifier)"
        )
        return card
    }

    @MainActor
    private func assertStableGridGeometry(
        _ cards: [XCUIElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let first = cards.first else {
            XCTFail("Grid assertion requires cards.", file: file, line: line)
            return
        }
        for card in cards {
            XCTAssertEqual(card.frame.width, 224, accuracy: 4, file: file, line: line)
            XCTAssertEqual(card.frame.height, first.frame.height, accuracy: 2, file: file, line: line)
        }
        for leftIndex in cards.indices {
            for rightIndex in cards.indices where rightIndex > leftIndex {
                let overlap = cards[leftIndex].frame.intersection(cards[rightIndex].frame)
                XCTAssertTrue(
                    overlap.isNull || overlap.isEmpty,
                    "Grid cards overlap: \(cards[leftIndex].identifier) and \(cards[rightIndex].identifier)",
                    file: file,
                    line: line
                )
            }
        }

        var orderedFrames = cards.map { card in card.frame }
        orderedFrames.sort { lhs, rhs in
            if abs(lhs.minY - rhs.minY) < 4 {
                return lhs.minX < rhs.minX
            }
            return lhs.minY < rhs.minY
        }

        var rows: [[CGRect]] = []
        for frame in orderedFrames {
            if let rowIndex = rows.firstIndex(where: {
                abs(($0.first?.minY ?? frame.minY) - frame.minY) < 4
            }) {
                rows[rowIndex].append(frame)
            } else {
                rows.append([frame])
            }
        }
        for row in rows {
            let ordered = row.sorted { $0.minX < $1.minX }
            for index in ordered.indices.dropFirst() {
                XCTAssertEqual(
                    ordered[index].minX - ordered[index - 1].maxX,
                    20,
                    accuracy: 4,
                    file: file,
                    line: line
                )
            }
        }
        for index in rows.indices.dropFirst() {
            guard let previous = rows[index - 1].first,
                  let current = rows[index].first else { continue }
            XCTAssertEqual(
                current.minY - previous.maxY,
                20,
                accuracy: 4,
                file: file,
                line: line
            )
            for (expected, actual) in zip(
                rows[0].sorted { $0.minX < $1.minX },
                rows[index].sorted { $0.minX < $1.minX }
            ) {
                XCTAssertEqual(actual.minX, expected.minX, accuracy: 4, file: file, line: line)
            }
        }
    }

    @MainActor
    private func assertBreadcrumb(
        _ expected: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let breadcrumb = app.descendants(matching: .any)[
            "MediaLibrary-Breadcrumb-current"
        ].firstMatch
        XCTAssertTrue(breadcrumb.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(breadcrumb.label, expected, file: file, line: line)
    }

    @MainActor
    private func createFolder(named name: String, in app: XCUIApplication) -> Bool {
        let manage = app.buttons["Manage media library"].firstMatch
        guard manage.waitForExistence(timeout: 10), manage.isEnabled else {
            XCTFail("Manage media library did not become available.")
            return false
        }
        manage.tap()
        let newFolder = app.buttons["New Library Folder"].firstMatch
        guard newFolder.waitForExistence(timeout: 5), newFolder.isEnabled else {
            XCTFail("New Library Folder did not become available.")
            return false
        }
        newFolder.tap()
        guard let field = systemAlertTextField(
            identifier: "MediaLibrary-NewFolder-name",
            placeholder: "Folder name",
            in: app
        ) else { return false }
        guard let create = systemAlertButton(
            identifier: "MediaLibrary-NewFolder-create",
            label: "Create",
            in: app
        ) else { return false }
        let cancel = app.buttons["Cancel"].firstMatch
        guard cancel.waitForExistence(timeout: 5) else {
            XCTFail("The New Library Folder alert did not expose Cancel.")
            return false
        }
        XCTAssertLessThan(
            cancel.frame.midX,
            create.frame.midX,
            "Cancel must appear before the primary Create action."
        )
        field.tap()
        field.typeText(name)
        create.tap()
        return true
    }

    @MainActor
    private func systemAlertTextField(
        identifier: String,
        placeholder: String,
        in app: XCUIApplication
    ) -> XCUIElement? {
        let alert = app.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else {
            XCTFail("The expected system alert did not appear.")
            return nil
        }
        let identified = app.textFields[identifier].firstMatch
        if identified.exists { return identified }
        let labeled = app.textFields[placeholder].firstMatch
        if labeled.exists { return labeled }
        let field = alert.textFields.firstMatch
        guard field.exists else {
            XCTFail("The system alert did not expose its text field.")
            return nil
        }
        return field
    }

    @MainActor
    private func systemAlertButton(
        identifier: String,
        label: String,
        in app: XCUIApplication
    ) -> XCUIElement? {
        let identified = app.buttons[identifier].firstMatch
        if identified.waitForExistence(timeout: 1) { return identified }
        let labeled = app.buttons[label].firstMatch
        guard labeled.waitForExistence(timeout: 5) else {
            XCTFail("The system alert did not expose \(label).")
            return nil
        }
        return labeled
    }
}
