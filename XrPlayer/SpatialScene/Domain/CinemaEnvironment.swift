import Foundation

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case darkTheatre
        case starryNight
        case sunsetNature

        public var displayName: String {
            switch self {
            case .darkTheatre: return "暗黑影院"
            case .starryNight: return "星空夜景"
            case .sunsetNature: return "自然日落"
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
