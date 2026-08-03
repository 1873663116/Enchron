import Foundation
import XCTest

nonisolated final class SequentialMediaPlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Sequential media regression requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testTwoRegisteredMediaOpenSequentiallyWithoutSessionOrSurfaceLeakage() throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 2
        )
        let app = XCUIApplication()
        app.launchEnvironment["ENCHRON_CONTROLS_AUTO_HIDE_SECONDS"] = "300"
        app.launch()

        var previousSession: String?
        for (index, identifier) in identifiers.prefix(2).enumerated() {
            let card = app.descendants(matching: .any)[identifier].firstMatch
            guard requireHittable(card, named: "Registered media \(identifier)", timeout: 30) else {
                return
            }
            card.tap()
            resolveResumeDecisionIfNeeded(in: app)

            let stateElement = app.descendants(matching: .any)[
                "PlayerUI-window-control-plane"
            ].firstMatch
            let first = try XCTUnwrap(waitForState(stateElement, timeout: 60) {
                $0.string("lifecycle")?.lowercased() == "playing"
                    && $0.string("attached") == "window"
                    && $0.bool("displayedPixel") == true
            })
            let currentSession = try XCTUnwrap(first.string("session"))
            XCTAssertNotEqual(currentSession, "none")
            if let previousSession {
                XCTAssertNotEqual(
                    currentSession,
                    previousSession,
                    "Opening the next media must establish a new Media Session."
                )
            }
            let second = try XCTUnwrap(waitForState(stateElement, timeout: 15) {
                ($0.double("position") ?? 0) > (first.double("position") ?? 0)
                    && ($0.uint64("videoSamples") ?? 0) > (first.uint64("videoSamples") ?? 0)
                    && ($0.uint64("rendererInputs") ?? 0) > (first.uint64("rendererInputs") ?? 0)
            })
            XCTAssertEqual(second.string("session"), currentSession)
            XCTAssertFalse(app.descendants(matching: .any)["PlayerUI-loadFailure-panel"].exists)
            attachState(second, name: "sequential-media-\(index + 1)-state")
            attachScreenshot(from: app, name: "sequential-media-\(index + 1)-playing")

            let back = app.buttons["PlayerUI-InfoBar-button-back"].firstMatch
            guard requireHittable(back, named: "Back to Media Library") else { return }
            back.tap()
            XCTAssertTrue(
                card.waitForExistence(timeout: 30),
                "Media Library did not return after closing \(identifier)."
            )
            XCTAssertTrue(
                stateElement.waitForNonExistence(timeout: 15),
                "The previous playback control plane remained after returning to Media Library."
            )
            previousSession = currentSession
        }
    }

    @MainActor
    private func resolveResumeDecisionIfNeeded(in app: XCUIApplication) {
        let resume = app.buttons["PlayerUI-resumeDecision-primary"].firstMatch
        if resume.waitForExistence(timeout: 2) {
            resume.tap()
        }
    }
}
