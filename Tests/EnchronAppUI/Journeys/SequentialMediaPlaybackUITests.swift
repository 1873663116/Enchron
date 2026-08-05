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
    func testSequentialMediaSessionsRemainIsolated() throws {
        let identifiers = try VisionProRegressionConfiguration.mediaCardIdentifiers(
            minimumCount: 2
        )
        let app = launchVisionProRegressionApp()

        var previousSession: String?
        for (index, identifier) in identifiers.prefix(2).enumerated() {
            guard let card = waitForHittableRegisteredMediaCard(
                identifier: identifier,
                in: app,
                timeout: 30
            ) else {
                XCTFail("Registered media \(identifier) did not become hittable.")
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
        attachHumanReviewBoundary(
            "Review the two playback segments for stale frames, mixed audio, or controls from the previous Media Session that mechanical identity checks cannot detect.",
            name: "sequential-media-sessions-human-review"
        )
    }
}
