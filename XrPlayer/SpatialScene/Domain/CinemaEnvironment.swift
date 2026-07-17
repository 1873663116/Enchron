import Foundation

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case darkTheatre
        case starryNight
        case sunsetNature

        public init?(preferenceValue: String?) {
            guard let preferenceValue else { return nil }
            switch preferenceValue {
            case Self.darkTheatre.rawValue, "Dark Cinema": self = .darkTheatre
            case Self.starryNight.rawValue, "Starry Night": self = .starryNight
            case Self.sunsetNature.rawValue, "Nature Sunset": self = .sunsetNature
            default: return nil
            }
        }

        public var displayName: String {
            switch self {
            case .darkTheatre: return "Dark Theatre"
            case .starryNight: return "Starry Night"
            case .sunsetNature: return "Nature Sunset"
            }
        }

        public var skyboxAssetName: String? {
            switch self {
            case .darkTheatre: return nil
            case .starryNight: return "StarryNight"
            case .sunsetNature: return "SunsetNature"
            }
        }
    }
}
