import Foundation
import XCTest

nonisolated final class DockedPlacementUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Docked placement regression requires Apple Vision Pro.")
#endif
    }

    @MainActor
    func testRestoreDefaultsUsesTheSpecifiedFourMeterDistance() async throws {
        let fixtureURL = try VisionProRegressionConfiguration.fixtureURL()
        try await VisionProRegressionConfiguration.requireReachableFixture(fixtureURL)
        let app = launchSpatialFixtureApp(fixtureURL: fixtureURL)
        try enterDocked(in: app)

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        _ = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceAnchorMatched") == true
        })

        let settings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        guard requireHittable(settings, named: "Docked Settings") else { return }
        settings.tap()
        let reset = app.buttons["PlayerPanel-DockedPlacement-reset"].firstMatch
        guard requireHittable(reset, named: "Restore Defaults") else { return }
        reset.tap()

        let restored = try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            $0.string("presentation") == "docked"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceRenderingReady") == true
        })
        XCTAssertEqual(
            restored.double("screenDistance") ?? .nan,
            4.0,
            accuracy: 0.001,
            "Restore Defaults must use the specified four-meter user-to-screen distance."
        )
        XCTAssertEqual(
            restored.double("screenElevation") ?? .nan,
            0.0,
            accuracy: 0.001
        )
        assertSurfaceMatchesPlacement(restored)
        attachState(restored, name: "docked-placement-specified-defaults")
        attachScreenshot(from: app, name: "docked-placement-specified-defaults")
    }

    @MainActor
    func testPlacementControlsChangeTheActualSurfaceAndPersistAcrossRoundTrip() async throws {
        let fixtureURL = try VisionProRegressionConfiguration.fixtureURL()
        try await VisionProRegressionConfiguration.requireReachableFixture(fixtureURL)
        let app = launchSpatialFixtureApp(fixtureURL: fixtureURL)
        try enterDocked(in: app)

        let spatialState = app.descendants(matching: .any)[
            "PlayerUI-spatial-state"
        ].firstMatch
        let initial = try XCTUnwrap(waitForState(spatialState, timeout: 30) {
            $0.string("presentation") == "docked"
                && $0.bool("surfaceSettled") == true
                && $0.bool("surfaceAnchorMatched") == true
        })
        assertSurfaceMatchesPlacement(initial)

        let settings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        guard requireHittable(settings, named: "Docked Settings") else { return }
        settings.tap()

        let size = app.descendants(matching: .any)[
            "PlayerPanel-ScreenSize-slider"
        ].firstMatch
        let distance = app.descendants(matching: .any)[
            "PlayerPanel-Distance-slider"
        ].firstMatch
        let elevation = app.descendants(matching: .any)[
            "PlayerPanel-Elevation-slider"
        ].firstMatch

        let initialScale = try XCTUnwrap(initial.double("screenScale"))
        let initialDistance = try XCTUnwrap(initial.double("screenDistance"))
        let initialElevation = try XCTUnwrap(initial.double("screenElevation"))
        dragDetentedSlider(
            size,
            from: normalized(initialScale, lower: 0.5, upper: 2.5),
            to: 0.75,
            named: "Screen Size"
        )
        dragDetentedSlider(
            distance,
            from: normalized(initialDistance, lower: 0.5, upper: 10),
            to: 0.25,
            named: "Distance"
        )
        dragDetentedSlider(
            elevation,
            from: normalized(initialElevation, lower: -80, upper: 80),
            to: 0.75,
            named: "Elevation"
        )

        let adjusted = try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            abs(($0.double("screenScale") ?? 0) - 2.0) < 0.06
                && abs(($0.double("screenDistance") ?? 0) - 2.875) < 0.06
                && abs(($0.double("screenElevation") ?? 0) - 40.0) < 0.6
                && abs(($0.double("surfaceLocalScaleX") ?? 0) - 2.0) < 0.06
        })
        assertSurfaceMatchesPlacement(adjusted)
        attachState(adjusted, name: "docked-placement-adjusted")
        attachScreenshot(from: app, name: "docked-placement-01-adjusted")

        let exitSpatial = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        guard requireHittable(exitSpatial, named: "Return to Window") else { return }
        exitSpatial.tap()
        let windowState = app.descendants(matching: .any)[
            "PlayerUI-window-control-plane"
        ].firstMatch
        _ = try XCTUnwrap(waitForState(windowState, timeout: 90) {
            $0.string("attached") == "window"
        })

        try enterDocked(in: app)
        let restored = try XCTUnwrap(waitForState(spatialState, timeout: 90) {
            $0.string("presentation") == "docked"
                && abs(($0.double("screenScale") ?? 0) - 2.0) < 0.06
                && abs(($0.double("screenDistance") ?? 0) - 2.875) < 0.06
                && abs(($0.double("screenElevation") ?? 0) - 40.0) < 0.6
        })
        assertSurfaceMatchesPlacement(restored)

        let restoredSettings = app.descendants(matching: .any)[
            "PlayerPanel-button-settings"
        ].firstMatch
        guard requireHittable(restoredSettings, named: "Docked Settings after return") else {
            return
        }
        restoredSettings.tap()
        let reset = app.buttons["PlayerPanel-DockedPlacement-reset"].firstMatch
        guard requireHittable(reset, named: "Restore Defaults") else { return }
        reset.tap()

        let resetState = try XCTUnwrap(waitForState(spatialState, timeout: 20) {
            abs(($0.double("screenScale") ?? .nan) - initialScale) < 0.001
                && abs(($0.double("screenDistance") ?? .nan) - initialDistance) < 0.001
                && abs(($0.double("screenElevation") ?? .nan) - initialElevation) < 0.001
        })
        assertSurfaceMatchesPlacement(resetState)
        attachState(resetState, name: "docked-placement-restored-defaults")
        attachScreenshot(from: app, name: "docked-placement-02-restored-defaults")
    }

    @MainActor
    private func enterDocked(in app: XCUIApplication) throws {
        let dock = app.descendants(matching: .any)["PlayerUI-TopAction-dock"].firstMatch
        guard requireHittable(dock, named: "Dock", timeout: 30) else { return }
        dock.tap()
        let day = app.descendants(matching: .any)["PlayerUI-DockMenu-day"].firstMatch
        guard requireHittable(day, named: "Dock with Day") else { return }
        day.tap()
        let exit = app.descendants(matching: .any)[
            "PlayerPanel-button-exit-spatial"
        ].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 90))
    }

    private func normalized(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> CGFloat {
        CGFloat((value - lower) / (upper - lower))
    }

    private func assertSurfaceMatchesPlacement(
        _ state: RegressionStateSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let distance = state.double("screenDistance") ?? .nan
        let elevation = state.double("screenElevation") ?? .nan
        let scale = state.double("screenScale") ?? .nan
        XCTAssertEqual(
            state.double("surfaceWorldDistance") ?? .nan,
            distance,
            accuracy: 0.03,
            file: file,
            line: line
        )
        XCTAssertEqual(
            state.double("surfaceWorldElevation") ?? .nan,
            elevation,
            accuracy: 0.5,
            file: file,
            line: line
        )
        for key in [
            "surfaceLocalScaleX",
            "surfaceLocalScaleY",
            "surfaceLocalScaleZ"
        ] {
            XCTAssertEqual(
                state.double(key) ?? .nan,
                scale,
                accuracy: 0.01,
                "Docked surface scale is not uniform or does not match Screen Size.",
                file: file,
                line: line
            )
        }
        XCTAssertGreaterThan(
            state.double("surfaceForwardToUserDot") ?? -1,
            0.995,
            "Docked surface is not facing the user.",
            file: file,
            line: line
        )
        XCTAssertEqual(state.bool("surfaceAnchorMatched"), true, file: file, line: line)
        XCTAssertEqual(state.bool("surfaceRenderingReady"), true, file: file, line: line)
    }
}
