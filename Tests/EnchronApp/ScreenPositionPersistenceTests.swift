import XCTest
@testable import Enchron

nonisolated final class ScreenPositionPersistenceTests: XCTestCase {
    func testScreenPlacementRoundTripsScaleAndAnchorRelativeOffsets() async throws {
        let suite = "xrplayer.tests.screen-position.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ScreenPositionStore(defaults: defaults)

        await store.savePosition(
            for: "darkTheatre",
            depthOffsetMeters: 0.25,
            verticalOffsetMeters: -0.1,
            angleDegrees: 4,
            screenScale: 1.3
        )

        let loaded = await store.loadPosition(for: "darkTheatre")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.depthOffsetMeters, 0.25)
        XCTAssertEqual(saved.verticalOffsetMeters, -0.1)
        XCTAssertEqual(saved.viewAngleDegrees, 4)
        XCTAssertEqual(saved.screenScale, 1.3)
    }

    func testLegacyAbsoluteDistanceRecordMigratesToAnchorDefaults() async throws {
        let suite = "xrplayer.tests.screen-position-legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "distanceMeters": 8.0,
                "verticalOffsetMeters": 0.2,
                "angleDegrees": 3.0
            ]),
            forKey: "xrplayer.screenPos.darkTheatre"
        )

        let loaded = await ScreenPositionStore(defaults: defaults).loadPosition(for: "darkTheatre")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.depthOffsetMeters, 0)
        XCTAssertEqual(saved.verticalOffsetMeters, 0.2)
        XCTAssertEqual(saved.viewAngleDegrees, 3)
        XCTAssertEqual(saved.screenScale, 1.3)
    }
}
