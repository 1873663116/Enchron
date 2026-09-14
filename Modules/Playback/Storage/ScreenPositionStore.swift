import Foundation

public nonisolated struct SavedScreenPosition: Sendable, Equatable {
    public let environmentID: String
    public let distanceMeters: Double
    public let elevationDegrees: Double
    public let screenScale: Double
    public let viewerHeightMeters: Double

    public init(
        environmentID: String,
        distanceMeters: Double,
        elevationDegrees: Double,
        screenScale: Double,
        viewerHeightMeters: Double = 0
    ) {
        self.environmentID = environmentID
        self.distanceMeters = distanceMeters
        self.elevationDegrees = elevationDegrees
        self.screenScale = screenScale
        self.viewerHeightMeters = viewerHeightMeters
    }
}

public nonisolated protocol ScreenPositionStoring: Sendable {
    func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        elevationDegrees: Double,
        screenScale: Double,
        viewerHeightMeters: Double
    ) async

    func loadPosition(for environmentID: String) async -> SavedScreenPosition?
}

nonisolated final class ScreenPositionStore: ScreenPositionStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let keyPrefix = "enchron.screenPos."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func savePosition(
        for environmentID: String,
        distanceMeters: Double,
        elevationDegrees: Double,
        screenScale: Double,
        viewerHeightMeters: Double
    ) async {
        let entry = Entry(
            distanceMeters: distanceMeters,
            elevationDegrees: elevationDegrees,
            screenScale: screenScale,
            viewerHeightMeters: viewerHeightMeters
        )
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: Self.keyPrefix + environmentID)
        }
    }

    func loadPosition(for environmentID: String) async -> SavedScreenPosition? {
        guard let data = defaults.data(forKey: Self.keyPrefix + environmentID),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return .init(
            environmentID: environmentID,
            distanceMeters: entry.distanceMeters
                ?? PlaybackDockedPlacementLimits.fallback.defaultDistance,
            elevationDegrees: entry.elevationDegrees
                ?? PlaybackDockedPlacementLimits.fallback.defaultElevationDegrees,
            screenScale: entry.screenScale
                ?? PlaybackDockedPlacementLimits.fallback.defaultScreenHeight,
            viewerHeightMeters: entry.verticalOffsetMeters ?? 0
        )
    }

    private struct Entry: Codable, Sendable {
        let distanceMeters: Double?
        let elevationDegrees: Double?
        let screenScale: Double?
        let depthOffsetMeters: Double?
        let verticalOffsetMeters: Double?
        let angleDegrees: Double?

        init(distanceMeters: Double, elevationDegrees: Double, screenScale: Double, viewerHeightMeters: Double) {
            self.distanceMeters = distanceMeters
            self.elevationDegrees = elevationDegrees
            self.screenScale = screenScale
            depthOffsetMeters = nil
            verticalOffsetMeters = viewerHeightMeters
            angleDegrees = nil
        }
    }
}

public nonisolated enum PlaybackPresentationStorage {
    public static func makeScreenPositionStore(
        suiteName: String? = nil
    ) -> any ScreenPositionStoring {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        return ScreenPositionStore(defaults: defaults)
    }
}
