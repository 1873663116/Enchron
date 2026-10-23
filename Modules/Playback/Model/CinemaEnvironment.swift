import EnvironmentSceneContract
import Foundation
import OceanEnvironment
import QuietRoomEnvironment
import RealityKit
import TidalEnvironment

public nonisolated enum SpatialSceneDomain {}

nonisolated extension SpatialSceneDomain {
    public enum CinemaEnvironment: String, Sendable, CaseIterable, Codable {
        case quietRoom = "quiet-room"
        case ocean
        case tidal

        public static let cardEnvironments: [Self] = [.ocean, .tidal]

        public var isCardEnvironment: Bool {
            self != .quietRoom
        }

        public var supportsDarkAppearance: Bool {
            self != .quietRoom
        }

        public var displayName: String {
            switch self {
            case .quietRoom: "Quiet Room"
            case .ocean: "Ocean"
            case .tidal: "Tidal"
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
    public static let fallbackDescriptor = EnvironmentSceneDescriptor(
        identifier: "fallback",
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
        case .tidal: TidalEnvironmentScene.descriptor
        }
    }

    public static func geometry(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> EnvironmentSceneGeometry {
        descriptor(for: environment).geometry
    }

    public static func defaultScreenHeightMeters(forEnvironmentID environmentID: String) -> Double {
        guard let environment = SpatialSceneDomain.CinemaEnvironment(rawValue: environmentID) else {
            return fallbackDescriptor.geometry.defaultScreenHeightMeters
        }
        return geometry(for: environment).defaultScreenHeightMeters
    }

    @MainActor private static var scenes: [SpatialSceneDomain.CinemaEnvironment: any EnvironmentScene] = [:]
    @MainActor private static var prefetchTasks: [SpatialSceneDomain.CinemaEnvironment: Task<Entity, Error>] = [:]
    @MainActor private static var prefetchOwners: [SpatialSceneDomain.CinemaEnvironment: Set<EnvironmentPrefetchOwner>] = [:]
    @MainActor private static var prefetchStarted: [SpatialSceneDomain.CinemaEnvironment: ContinuousClock.Instant] = [:]

    @MainActor
    public static func prefetch(
        _ environments: [SpatialSceneDomain.CinemaEnvironment],
        owner: EnvironmentPrefetchOwner
    ) {
        let requested = Set(environments)
        for environment in SpatialSceneDomain.CinemaEnvironment.allCases
        where !requested.contains(environment) {
            guard var owners = prefetchOwners[environment], owners.remove(owner) != nil else {
                continue
            }
            guard owners.isEmpty else {
                prefetchOwners[environment] = owners
                continue
            }
            prefetchOwners[environment] = nil
            prefetchTasks[environment]?.cancel()
            prefetchTasks[environment] = nil
            prefetchStarted[environment] = nil
            scenes[environment] = nil
        }
        for environment in requested {
            prefetchOwners[environment, default: []].insert(owner)
            guard prefetchTasks[environment] == nil else { continue }
            let scene = scene(for: environment)
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

    @MainActor
    public static func waitForPrefetch(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) async throws {
        guard let task = prefetchTasks[environment] else { return }
        do {
            _ = try await task.value
        } catch {
            if prefetchTasks[environment] == task {
                prefetchTasks[environment] = nil
                prefetchOwners[environment] = nil
                prefetchStarted[environment] = nil
                scenes[environment] = nil
            }
            throw error
        }
    }

    @MainActor
    public static func takePrefetch(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> Task<Entity, Error>? {
        defer {
            prefetchTasks[environment] = nil
            prefetchOwners[environment] = nil
            prefetchStarted[environment] = nil
        }
        return prefetchTasks[environment]
    }

    @MainActor
    public static func prefetchStartedInstant(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> ContinuousClock.Instant? {
        prefetchStarted[environment]
    }

    @MainActor
    public static func scene(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> any EnvironmentScene {
        if let existing = scenes[environment] {
            return existing
        }
        let scene: any EnvironmentScene = switch environment {
        case .quietRoom: QuietRoomEnvironmentScene()
        case .ocean: OceanEnvironmentScene()
        case .tidal: TidalEnvironmentScene()
        }
        scenes[environment] = scene
        return scene
    }
}

public struct EnvironmentPrefetchOwner: Hashable, Sendable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var description: String { name }

    public static let views = EnvironmentPrefetchOwner("views")
    public static let session = EnvironmentPrefetchOwner("session")
}
