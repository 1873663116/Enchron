import XCTest

/// UI test confirming the fused `FusedPlayerPanel` — not a one-off control —
/// is what mounts as the live window-playback surface (ADR-0009 consolidation).
///
/// Note: this asserts presence, not ornament-button taps. visionOS ornament
/// content is hosted in 3D space and its buttons are not reliably hittable under
/// XCUITest, so the fine-grained transport interactions (PLAY-05 play/pause,
/// PLAY-25 settings panel) are covered deterministically by `FakePlaybackSource`
/// unit tests + the panel's live binding rather than by simulated ornament taps.
///
/// `nonisolated` opts the class out of the project-wide default `MainActor`
/// isolation; the test methods opt back in for the `XCUIApplication` API.
nonisolated final class PlaybackDeckUITests: XCTestCase {

    @MainActor
    func testPolishedDeckIsLivePlaybackSurface() {
        let app = XCUIApplication()
        app.launch()

        let card = app.descendants(matching: .any)["FileBrowsing-grid-video-Interstellar.mkv"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Fake catalog card should exist")
        card.tap()

        // FILE-01 → the fused FusedPlayerPanel mounts as the playback chrome:
        // its transport play button, ⋯ menu, and ≡ settings entry are all present.
        let play = app.descendants(matching: .any)["PlayerPanel-button-play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20),
                      "Fused panel play button should mount as the live transport")
        XCTAssertTrue(play.label == "Play" || play.label == "Pause",
                      "Play button label should reflect live playback state, got \(play.label)")

        let more = app.descendants(matching: .any)["PlayerPanel-menu-more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5),
                      "Fused panel ⋯ menu (subtitles / audio / speed) should be present")

        let panelButton = app.descendants(matching: .any)["PlayerPanel-button-panel"].firstMatch
        XCTAssertTrue(panelButton.waitForExistence(timeout: 5),
                      "Fused panel ≡ settings entry should be present")
    }
}
