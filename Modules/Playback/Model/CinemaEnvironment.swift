import EnvironmentSceneContract
import Foundation
import OceanEnvironment
import QuietRoomEnvironment

public nonisolated enum SpatialSceneDomain {}

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case quietRoom = "quiet-room"
        case ocean
        case placeholderRed = "placeholder-red"
        case placeholderGreen = "placeholder-green"
        case placeholderBlue = "placeholder-blue"

        public static let defaultEnvironment: Self = .quietRoom

        public static let cardEnvironments: [Self] = [
            .ocean,
            .placeholderRed,
            .placeholderGreen,
            .placeholderBlue
        ]

        public var isCardEnvironment: Bool {
            self != .quietRoom
        }

        public var supportsDarkAppearance: Bool {
            self != .quietRoom
        }

        public var isSceneBacked: Bool {
            switch self {
            case .quietRoom, .ocean: true
            case .placeholderRed, .placeholderGreen, .placeholderBlue: false
            }
        }

        public var placeholderColor: SIMD3<Float>? {
            switch self {
            case .placeholderRed: [0.85, 0.12, 0.12]
            case .placeholderGreen: [0.12, 0.70, 0.20]
            case .placeholderBlue: [0.12, 0.35, 0.90]
            case .quietRoom, .ocean: nil
            }
        }

        public var displayName: String {
            switch self {
            case .quietRoom: "Quiet Room"
            case .ocean: "Ocean"
            case .placeholderRed: "Red"
            case .placeholderGreen: "Green"
            case .placeholderBlue: "Blue"
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

        public var appearance: EnvironmentSceneContract.EnvironmentAppearance {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

}

public nonisolated enum EnvironmentSceneMapping {
    public static let placeholderDescriptor = EnvironmentSceneDescriptor(
        identifier: "placeholder",
        geometry: EnvironmentSceneGeometry(
            defaultDistanceMeters: 12,
            defaultScreenHeightMeters: 8,
            screenHeightRangeMeters: 8...8
        ),
        supportsDarkAppearance: true
    )

    public static func descriptor(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> EnvironmentSceneDescriptor {
        switch environment {
        case .quietRoom: QuietRoomEnvironmentScene.descriptor
        case .ocean: OceanEnvironmentScene.descriptor
        case .placeholderRed, .placeholderGreen, .placeholderBlue: placeholderDescriptor
        }
    }

    public static func geometry(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> EnvironmentSceneGeometry {
        descriptor(for: environment).geometry
    }

    public static func defaultScreenHeightMeters(forEnvironmentID environmentID: String) -> Double {
        guard let environment = SpatialSceneDomain.CinemaEnvironment(rawValue: environmentID) else {
            return placeholderDescriptor.geometry.defaultScreenHeightMeters
        }
        return geometry(for: environment).defaultScreenHeightMeters
    }

    @MainActor private static var scenes: [SpatialSceneDomain.CinemaEnvironment: any EnvironmentScene] = [:]

    @MainActor
    public static func scene(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> (any EnvironmentScene)? {
        if let existing = scenes[environment] {
            return existing
        }
        let scene: (any EnvironmentScene)? = switch environment {
        case .quietRoom: QuietRoomEnvironmentScene()
        case .ocean: OceanEnvironmentScene()
        case .placeholderRed, .placeholderGreen, .placeholderBlue: nil
        }
        if let scene {
            scenes[environment] = scene
        }
        return scene
    }
}
