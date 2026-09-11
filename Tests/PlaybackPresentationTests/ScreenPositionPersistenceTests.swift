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
            for: "ocean",
            distanceMeters: 2.4,
            elevationDegrees: 12,
            screenScale: 1.3
        )
        await store.savePosition(
            for: "placeholder-red",
            distanceMeters: 4.8,
            elevationDegrees: -18,
            screenScale: 0.8
        )

        let storedOcean = await store.loadPosition(for: "ocean")
        let storedPlaceholderRed = await store.loadPosition(for: "placeholder-red")
        let ocean = try XCTUnwrap(storedOcean)
        let placeholderRed = try XCTUnwrap(storedPlaceholderRed)
        XCTAssertEqual(ocean.distanceMeters, 2.4)
        XCTAssertEqual(ocean.elevationDegrees, 12)
        XCTAssertEqual(ocean.screenScale, 1.3)
        XCTAssertEqual(placeholderRed.distanceMeters, 4.8)
        XCTAssertEqual(placeholderRed.elevationDegrees, -18)
        XCTAssertEqual(placeholderRed.screenScale, 0.8)
    }

    func testSavedScreenPositionRoundTripsWithoutClampingIntoAnyEnvironmentsLimits() async throws {
        let suite = "enchron.tests.screen-position-unclamped.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PlaybackPresentationStorage.makeScreenPositionStore(suiteName: suite)

        await store.savePosition(
            for: "quiet-room",
            distanceMeters: 200,
            elevationDegrees: -45,
            screenScale: 40
        )

        let loadedPosition = await store.loadPosition(for: "quiet-room")
        let loaded = try XCTUnwrap(loadedPosition)
        XCTAssertEqual(loaded.distanceMeters, 200)
        XCTAssertEqual(loaded.elevationDegrees, -45)
        XCTAssertEqual(loaded.screenScale, 40)
    }

    func testMissingFieldsFallBackToPlaybackDockedPlacementLimitsFallback() async throws {
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
        XCTAssertEqual(saved.distanceMeters, PlaybackDockedPlacementLimits.fallback.defaultDistance)
        XCTAssertEqual(
            saved.elevationDegrees,
            PlaybackDockedPlacementLimits.fallback.defaultElevationDegrees
        )
        XCTAssertEqual(saved.screenScale, PlaybackDockedPlacementLimits.fallback.defaultScreenHeight)
    }
}
