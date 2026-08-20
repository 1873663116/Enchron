import Foundation

public nonisolated enum SpatialSceneDomain {}

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case scenicOne = "scenic-one"
        case scenicTwo = "scenic-two"
        case scenicThree = "scenic-three"
        case skybox

        public static let defaultScenic: Self = .scenicOne

        public static let scenicEnvironments: [Self] = [
            .scenicOne,
            .scenicTwo,
            .scenicThree,
        ]

        public init?(preferenceValue: String?) {
            guard let preferenceValue else { return nil }
            if let environment = Self(rawValue: preferenceValue), environment.isScenic {
                self = environment
                return
            }
            // Migrate the former single placeholder environment to the first
            // stable Scenic identity. Skybox is intentionally never a default.
            if preferenceValue == "enchron" {
                self = .defaultScenic
                return
            }
            return nil
        }

        public var isScenic: Bool {
            self != .skybox
        }

        public var displayName: String {
            switch self {
            case .scenicOne: "Scenic Environment 1"
            case .scenicTwo: "Scenic Environment 2"
            case .scenicThree: "Scenic Environment 3"
            case .skybox: "Skybox"
            }
        }
    }

    public enum EnvironmentEffect: String, Sendable, CaseIterable, Codable {
        case light
        case dark

        public static let inactiveFallback: Self = .light

        public var displayName: String {
            switch self {
            case .light: "Light Mode"
            case .dark: "Dark Mode"
            }
        }
    }

    public typealias EnvironmentAppearance = EnvironmentEffect
}

public nonisolated enum EnvironmentSceneMapping {
    public static let worldSceneName = "Immersive"

    public static func sceneName(forEnvironmentID _: String) -> String { worldSceneName }
    public static func defaultScreenScale(forEnvironmentID _: String) -> Double { 1.3 }
}
