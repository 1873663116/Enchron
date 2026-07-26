import Foundation

public nonisolated enum SpatialSceneDomain {}

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case enchron

        public init?(preferenceValue: String?) {
            guard preferenceValue != nil else { return nil }
            self = .enchron
        }

        public var displayName: String { "Enchron Environment" }
    }

    public enum EnvironmentEffect: String, Sendable, CaseIterable, Codable {
        case day
        case night

        public static let inactiveFallback: Self = .day

        public var displayName: String {
            switch self {
            case .day: "Day"
            case .night: "Night"
            }
        }
    }

    public typealias EnvironmentAppearance = EnvironmentEffect
}

public nonisolated enum EnvironmentSceneMapping {
    public static let worldSceneName = "world"

    public static func sceneName(forEnvironmentID _: String) -> String { worldSceneName }
    public static func defaultScreenScale(forEnvironmentID _: String) -> Double { 1.3 }
}
