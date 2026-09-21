import EnvironmentSceneContract
import Foundation
import OceanEnvironment
import QuietRoomEnvironment
import RealityKit

public nonisolated enum SpatialSceneDomain {}

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case quietRoom = "quiet-room"
        case ocean
        case placeholderRed = "placeholder-red"
        case placeholderGreen = "placeholder-green"
        case placeholderBlue = "placeholder-blue"

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
    @MainActor private static var prefetchTasks: [SpatialSceneDomain.CinemaEnvironment: Task<Entity, Error>] = [:]
    @MainActor private static var prefetchStarted: [SpatialSceneDomain.CinemaEnvironment: ContinuousClock.Instant] = [:]

    /// Starts decoding `environments` ahead of an imminent open (dock menu
    /// shown, card toggled). Holds at most the requested batch: anything else
    /// is cancelled. Never decodes more than asked — the card catalog is not
    /// bulk-loaded.
    @MainActor
    public static func prefetch(_ environments: [SpatialSceneDomain.CinemaEnvironment]) {
        for stale in prefetchTasks.keys where !environments.contains(stale) {
            prefetchTasks[stale]?.cancel()
            prefetchTasks[stale] = nil
            prefetchStarted[stale] = nil
        }
        for environment in environments {
            guard prefetchTasks[environment] == nil,
                  let scene = scene(for: environment)
            else {
                continue
            }
            prefetchStarted[environment] = ContinuousClock().now
            prefetchTasks[environment] = Task { @MainActor in
                let root = try await scene.load()
                if let ocean = scene as? OceanEnvironmentScene {
                    ocean.prewarmRuntime(in: root)
                }
                try Task.checkCancellation()
                return root
            }
        }
    }

    /// Takes the in-flight or finished decode for `environment`, if any,
    /// cancelling the rest. Awaiting the returned task reuses the prefetched
    /// root instead of decoding twice.
    @MainActor
    public static func takePrefetch(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> Task<Entity, Error>? {
        for stale in prefetchTasks.keys where stale != environment {
            prefetchTasks[stale]?.cancel()
            prefetchTasks[stale] = nil
            prefetchStarted[stale] = nil
        }
        defer {
            prefetchTasks[environment] = nil
            prefetchStarted[environment] = nil
        }
        return prefetchTasks[environment]
    }

    /// When the decode for `environment` started, if prefetched. Lets the
    /// opener measure the true decode cost even though it began earlier.
    @MainActor
    public static func prefetchStartedInstant(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> ContinuousClock.Instant? {
        prefetchStarted[environment]
    }

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
