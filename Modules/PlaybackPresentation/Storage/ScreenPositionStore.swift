import Foundation


public nonisolated struct SavedScreenPosition: Sendable, Equatable {
    public let environmentID: String
    public let depthOffsetMeters: Double
    public let verticalOffsetMeters: Double
    public let viewAngleDegrees: Double
    public let screenScale: Double

    public init(
        environmentID: String,
        depthOffsetMeters: Double,
        verticalOffsetMeters: Double,
        viewAngleDegrees: Double,
        screenScale: Double
    ) {
        self.environmentID = environmentID
        self.depthOffsetMeters = min(max(depthOffsetMeters, -2.0), 2.0)
        self.verticalOffsetMeters = min(max(verticalOffsetMeters, -5.0), 5.0)
        self.viewAngleDegrees = min(max(viewAngleDegrees, -45.0), 45.0)
        self.screenScale = min(max(screenScale, 0.5), 2.5)
    }
}


public nonisolated protocol ScreenPositionStoring: Sendable {
    func savePosition(
        for environmentID: String,
        depthOffsetMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double,
        screenScale: Double
    ) async

    func loadPosition(for environmentID: String) async -> SavedScreenPosition?
}


public nonisolated final class ScreenPositionStore: ScreenPositionStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private static let keyPrefix = "xrplayer.screenPos."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func savePosition(
        for environmentID: String,
        depthOffsetMeters: Double,
        verticalOffsetMeters: Double,
        angleDegrees: Double,
        screenScale: Double
    ) async {
        let entry = Entry(
            depthOffsetMeters: depthOffsetMeters,
            verticalOffsetMeters: verticalOffsetMeters,
            angleDegrees: angleDegrees,
            screenScale: screenScale
        )
        if let data = try? JSONEncoder().encode(entry) {
            defaults.set(data, forKey: Self.keyPrefix + environmentID)
        }
    }

    public func loadPosition(
        for environmentID: String
    ) async -> SavedScreenPosition? {
        guard let data = defaults.data(forKey: Self.keyPrefix + environmentID),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
            return nil
        }
        return .init(
            environmentID: environmentID,
            depthOffsetMeters: entry.depthOffsetMeters ?? 0,
            verticalOffsetMeters: entry.verticalOffsetMeters,
            viewAngleDegrees: entry.angleDegrees,
            screenScale: entry.screenScale ?? 1.3
        )
    }

    private struct Entry: Codable, Sendable {
        let depthOffsetMeters: Double?
        let verticalOffsetMeters: Double
        let angleDegrees: Double
        let screenScale: Double?
    }
}
