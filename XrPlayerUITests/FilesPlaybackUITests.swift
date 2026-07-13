import XCTest

/// UI tests for the FakeApp Files → playback flow against the live app process.
///
/// Exercises the assembled `FilesScreen` (shared components fed by
/// `FileBrowsingViewModel` + `FakeFileDataSource`) and the FILE-01 direct-play
/// path through `PlaybackLaunchCoordinator` onto `FakePlaybackSource`.
///
/// `nonisolated` matches `SmokeLaunchUITests`: it opts the class out of the
/// project-wide default `MainActor` isolation; the test methods opt back in for
/// the `XCUIApplication` API.
nonisolated final class FilesPlaybackUITests: XCTestCase {

    @MainActor
    func testFilesScreenShowsFakeCatalog() {
        let app = XCUIApplication()
        app.launch()

        // LNCH-01 / FILE-01: the deterministic fake catalog renders on the new
        // Files screen as tappable grid cards.
        let card = app.descendants(matching: .any)["FileBrowsing-grid-video-Interstellar.mkv"]
        XCTAssertTrue(card.waitForExistence(timeout: 20),
                      "Files screen should render the fake catalog's Interstellar card")
    }

    @MainActor
    func testTappingFilmCardOpensPlayer() {
        let app = XCUIApplication()
        app.launch()

        let card = app.descendants(matching: .any)["FileBrowsing-grid-video-Interstellar.mkv"]
        XCTAssertTrue(card.waitForExistence(timeout: 20),
                      "Interstellar card should exist before tapping")
        card.tap()

        // FILE-01: tapping a film plays it directly (no detail page) — the fused
        // FusedPlayerPanel transport chrome appears, driven by FakePlaybackSource.
        let playPause = app.descendants(matching: .any)["PlayerPanel-button-play"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 20),
                      "Tapping a film should open the fused player panel (FILE-01)")
    }
}
