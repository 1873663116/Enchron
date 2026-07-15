import XCTest

/// UI tests for Files → playback against the live app process.
///
/// Exercises the assembled `FilesScreen` virtual library and the direct-play
/// path through `PlaybackLaunchCoordinator` and the test runtime fixture.
///
/// `nonisolated` matches `SmokeLaunchUITests`: it opts the class out of the
/// project-wide default `MainActor` isolation; the test methods opt back in for
/// the `XCUIApplication` API.
nonisolated final class FilesPlaybackUITests: XCTestCase {

    @MainActor
    func testFilesScreenShowsFixtureCatalog() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()

        let card = app.descendants(matching: .any)["MediaLibrary-grid-video-Interstellar.mkv"]
        XCTAssertTrue(card.waitForExistence(timeout: 20),
                      "Files screen should render the fixture catalog's Interstellar card")
    }

    @MainActor
    func testTappingFilmCardOpensPlayer() {
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_UI_TESTING"] = "1"
        app.launch()

        let card = app.descendants(matching: .any)["MediaLibrary-grid-video-Interstellar.mkv"]
        XCTAssertTrue(card.waitForExistence(timeout: 20),
                      "Interstellar card should exist before tapping")
        card.tap()

        let playbackSurface = app.descendants(matching: .any)["PlayerUI-window-playback"]
        XCTAssertTrue(playbackSurface.waitForExistence(timeout: 20),
                      "Tapping a film should open the window playback surface")
    }
}
