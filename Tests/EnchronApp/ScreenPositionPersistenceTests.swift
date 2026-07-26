import PlaybackPresentation
import XCTest
@testable import Enchron

nonisolated final class ScreenPositionPersistenceTests: XCTestCase {
    func testDockedPlacementRoundTripsDistanceElevationAndScale() async throws {
        let suite = "xrplayer.tests.screen-position.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite)

        await store.savePosition(
            for: "enchron-environment",
            distanceMeters: 2.4,
            elevationDegrees: 12,
            screenScale: 1.3
        )

        let loaded = await store.loadPosition(for: "enchron-environment")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.distanceMeters, 2.4)
        XCTAssertEqual(saved.elevationDegrees, 12)
        XCTAssertEqual(saved.screenScale, 1.3)
    }

    func testLegacyOffsetsDoNotMasqueradeAsUserCenteredPlacement() async throws {
        let suite = "xrplayer.tests.screen-position-legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "depthOffsetMeters": 1.5,
                "verticalOffsetMeters": 0.2,
                "angleDegrees": 3.0
            ]),
            forKey: "xrplayer.screenPos.enchron-environment"
        )

        let loaded = await PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite)
            .loadPosition(for: "enchron-environment")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.distanceMeters, PlaybackDockedPlacement.defaultDistance)
        XCTAssertEqual(saved.elevationDegrees, PlaybackDockedPlacement.defaultElevationDegrees)
        XCTAssertEqual(saved.screenScale, 1.3)
    }
}
