import Playback
import XCTest

nonisolated final class ScreenPositionPersistenceTests: XCTestCase {
    func testDockedPlacementRoundTripsDistanceElevationAndScale() async throws {
        let suite = "enchron.tests.screen-position.\(UUID().uuidString)"
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

    func testDockedPlacementIsStoredIndependentlyForEachEnvironmentIdentity() async throws {
        let suite = "enchron.tests.screen-position-isolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite)

        await store.savePosition(
            for: "scenic-one",
            distanceMeters: 2.4,
            elevationDegrees: 12,
            screenScale: 1.3
        )
        await store.savePosition(
            for: "scenic-two",
            distanceMeters: 4.8,
            elevationDegrees: -18,
            screenScale: 0.8
        )

        let storedScenicOne = await store.loadPosition(for: "scenic-one")
        let storedScenicTwo = await store.loadPosition(for: "scenic-two")
        let scenicOne = try XCTUnwrap(storedScenicOne)
        let scenicTwo = try XCTUnwrap(storedScenicTwo)
        XCTAssertEqual(scenicOne.distanceMeters, 2.4)
        XCTAssertEqual(scenicOne.elevationDegrees, 12)
        XCTAssertEqual(scenicOne.screenScale, 1.3)
        XCTAssertEqual(scenicTwo.distanceMeters, 4.8)
        XCTAssertEqual(scenicTwo.elevationDegrees, -18)
        XCTAssertEqual(scenicTwo.screenScale, 0.8)
    }

    func testLegacyOffsetsDoNotMasqueradeAsUserCenteredPlacement() async throws {
        let suite = "enchron.tests.screen-position-legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "depthOffsetMeters": 1.5,
                "verticalOffsetMeters": 0.2,
                "angleDegrees": 3.0
            ]),
            forKey: "enchron.screenPos.enchron-environment"
        )

        let loaded = await PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite)
            .loadPosition(for: "enchron-environment")
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.distanceMeters, PlaybackDockedPlacement.defaultDistance)
        XCTAssertEqual(saved.elevationDegrees, PlaybackDockedPlacement.defaultElevationDegrees)
        XCTAssertEqual(saved.screenScale, 1.3)
    }
}
