import Foundation
import XCTest

nonisolated final class SpatialHandoffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Spatial handoff regression requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testDockedTargetIsReadyBeforeWindowStopsBeingTheUsableSurface() async throws {
        let fixtureURL = try VisionProRegressionConfiguration.fixtureURL()
        try await VisionProRegressionConfiguration.requireReachableFixture(fixtureURL)
        let app = launchSpatialFixtureApp(fixtureURL: fixtureURL)

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let before = try XCTUnwrap(waitForState(windowState, timeout: 45) {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.string("attached") == "window"
        })
        let session = try XCTUnwrap(before.string("session"))
        let windowPlay = windowState.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(windowPlay, named: "Window Play/Pause") else { return }
        attachScreenshot(from: app, name: "docked-handoff-01-window")

        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock") else { return }
        dock.tap()
        let day = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        guard requireHittable(day, named: "Dock with Day") else { return }
        day.tap()

        let spatial = try observeHandoffWithoutUnusableGap(
            app: app,
            originalSurface: windowState,
            originalTransportControl: windowPlay,
            targetPresentation: "docked"
        )
        XCTAssertEqual(spatial.string("session"), session)
        XCTAssertEqual(spatial.string("attached"), "docked")
        XCTAssertEqual(spatial.bool("surfaceSettled"), true)
        XCTAssertEqual(spatial.bool("surfaceRenderingReady"), true)
        XCTAssertEqual(spatial.bool("surfaceAnchorMatched"), true)
        XCTAssertEqual(spatial.string("surfaceParent"), "PlaybackSurfaceAnchor")
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertTrue(windowState.waitForNonExistence(timeout: 15))
        attachState(spatial, name: "docked-handoff-state")
        attachScreenshot(from: app, name: "docked-handoff-02-settled")
    }

    @MainActor
    func testPanoramaTargetIsReadyBeforeWindowStopsBeingTheUsableSurface() async throws {
        let fixtureURL = try VisionProRegressionConfiguration.fixtureURL()
        try await VisionProRegressionConfiguration.requireReachableFixture(fixtureURL)
        let app = launchSpatialFixtureApp(fixtureURL: fixtureURL)

        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        let before = try XCTUnwrap(waitForState(windowState, timeout: 45) {
            $0.string("lifecycle")?.lowercased() == "playing"
                && $0.string("attached") == "window"
        })
        let session = try XCTUnwrap(before.string("session"))
        let windowPlay = windowState.descendants(matching: .any)[
            "PlayerPanel-button-play"
        ].firstMatch
        guard requireHittable(windowPlay, named: "Window Play/Pause") else { return }
        attachScreenshot(from: app, name: "panorama-handoff-01-window")

        let format = app.descendants(matching: .any)[
            "PlayerUI-TopAction-videoFormat"
        ].firstMatch
        guard requireHittable(format, named: "Video Format") else { return }
        format.tap()
        let panorama = app.descendants(matching: .any)[
            "PlayerUI-VideoFormat-Projection-360°"
        ].firstMatch
        guard requireHittable(panorama, named: "360 degree projection") else { return }
        panorama.tap()
        let apply = app.buttons["PlayerUI-VideoFormat-apply"].firstMatch
        guard requireHittable(apply, named: "Apply video format") else { return }
        apply.tap()

        let spatial = try observeHandoffWithoutUnusableGap(
            app: app,
            originalSurface: windowState,
            originalTransportControl: windowPlay,
            targetPresentation: "panorama"
        )
        XCTAssertEqual(spatial.string("session"), session)
        XCTAssertEqual(spatial.string("attached"), "panorama")
        XCTAssertEqual(spatial.string("environment"), "none")
        XCTAssertEqual(spatial.bool("surfaceSettled"), true)
        XCTAssertEqual(spatial.bool("surfaceRenderingReady"), true)
        XCTAssertFalse(app.descendants(matching: .any)["PlayerPanel-button-back"].exists)
        XCTAssertTrue(windowState.waitForNonExistence(timeout: 15))
        attachState(spatial, name: "panorama-handoff-state")
        attachScreenshot(from: app, name: "panorama-handoff-02-settled")
    }

    @MainActor
    private func observeHandoffWithoutUnusableGap(
        app: XCUIApplication,
        originalSurface: XCUIElement,
        originalTransportControl: XCUIElement,
        targetPresentation: String
    ) throws -> RegressionStateSnapshot {
        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let deadline = Date().addingTimeInterval(90)
        var samples: [String] = []
        var observedUnusableGap = false
        var observedTwoUsableInterfaces = false

        while Date() < deadline {
            let windowExists = originalSurface.exists
            let windowUsable = windowExists
                && originalTransportControl.exists
                && originalTransportControl.isHittable
            let targetUsable = exitSpatial.exists
                && exitSpatial.isHittable
                && spatialState.exists
            samples.append(
                "\(Date().timeIntervalSince1970):windowExists=\(windowExists);windowUsable=\(windowUsable);targetUsable=\(targetUsable)"
            )
            if windowUsable == false && targetUsable == false {
                observedUnusableGap = true
                break
            }
            if windowUsable && targetUsable {
                observedTwoUsableInterfaces = true
                break
            }
            if targetUsable {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        let timeline = XCTAttachment(string: samples.joined(separator: "\n"))
        timeline.name = "\(targetPresentation)-handoff-timeline"
        timeline.lifetime = .keepAlways
        add(timeline)
        XCTAssertFalse(
            observedUnusableGap,
            "Window playback stopped being usable before the target Player Controls Window became usable."
        )
        XCTAssertFalse(
            observedTwoUsableInterfaces,
            "Window playback and the target Player Controls Window were usable at the same time."
        )
        guard requireHittable(exitSpatial, named: "Return to Window", timeout: 5) else {
            throw DeviceRegressionFailure.targetControlsUnavailable(targetPresentation)
        }
        XCTAssertFalse(
            app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch.isHittable,
            "The Window and spatial playback interfaces must not both accept Presentation input."
        )
        return try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            $0.string("presentation") == targetPresentation
                && $0.string("attached") == targetPresentation
                && $0.bool("surfaceSettled") == true
        })
    }
}
