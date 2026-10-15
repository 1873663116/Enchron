import EnvironmentSceneContract
import Foundation
import OSLog
import RealityKit
import simd

public final class TidalEnvironmentScene: EnvironmentScene {
    public nonisolated static let descriptor = EnvironmentSceneDescriptor(
        identifier: "tidal",
        geometry: EnvironmentSceneGeometry(
            defaultDistanceMeters: 13.550063,
            distanceRangeMeters: 13.550063...13.550063,
            defaultScreenHeightMeters: 8,
            screenHeightRangeMeters: 8...8,
            viewerHeightRangeMeters: 0...0
        ),
        supportsDarkAppearance: true,
        videoReflectionSource: .dockingRegion
    )

    private static let textureNames = [
        "FloorPlane_color": "floor-dark",
        "WallLeftPlane_color": "wall-left-dark",
        "RecessPlane_color": "recess-dark"
    ]

    private let logger = Logger(subsystem: "com.xiongzhipeng.Enchron", category: "TidalEnvironment")
    public private(set) var restPose: EnvironmentScreenRestPose?
    public var descriptor: EnvironmentSceneDescriptor { Self.descriptor }

    public init() {}

    public func load() async throws -> Entity {
        let started = ContinuousClock.now
        guard let sceneURL = Bundle.module.url(forResource: "tidal", withExtension: "reality") else {
            throw EnvironmentSceneLoadingError.resourceMissing("tidal")
        }
        guard let parameterURL = Bundle.module.url(forResource: "dark-parameters", withExtension: "bin") else {
            throw EnvironmentSceneLoadingError.resourceMissing("dark-parameters")
        }
        let parameterTask = Task.detached(priority: .userInitiated) {
            try TidalDarkParameters.load(from: parameterURL)
        }
        defer { parameterTask.cancel() }
        let root = try await Entity(contentsOf: sceneURL)
        root.position.y += TidalScenePlacement.rootHeight
        for (name, offset) in TidalScenePlacement.debrisOffsets {
            guard let entity = root.findEntity(named: name) else {
                throw EnvironmentSceneLoadingError.entityMissing(name)
            }
            entity.setPosition(entity.position(relativeTo: root) + offset, relativeTo: root)
        }
        logger.notice("load stage=entities elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
        try Task.checkCancellation()
        var darkTextures: [String: TextureResource] = [:]
        for (parameter, name) in Self.textureNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ktx") else {
                throw EnvironmentSceneLoadingError.resourceMissing(name)
            }
            darkTextures[parameter] = try await TextureResource(contentsOf: url, options: .init(semantic: .color))
            try Task.checkCancellation()
        }
        logger.notice("load stage=water elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
        guard var pose = EnvironmentScreenRestPose.dockingRegion(
            in: root, screenHeight: Float(Self.descriptor.geometry.defaultScreenHeightMeters)
        ) else {
            throw EnvironmentSceneLoadingError.entityMissing(EnvironmentSceneEntityName.dockingRegion)
        }
        pose.center.y += 0.65
        func firstAtlas(in entity: Entity) -> TextureResource? {
            if let model = entity.components[ModelComponent.self] {
                for material in model.materials {
                    if let graph = material as? ShaderGraphMaterial,
                       case .textureResource(let atlas)? = graph.getParameter(name: "SceneAtlas_color") {
                        return atlas
                    }
                }
            }
            for child in entity.children {
                if let atlas = firstAtlas(in: child) { return atlas }
            }
            return nil
        }
        guard let atlas = firstAtlas(in: root) else {
            throw EnvironmentSceneLoadingError.entityMissing("SceneAtlas_color")
        }
        let parameters = try await parameterTask.value
        let darkTemplate = try await TidalDarkMaterial.prepare(parameters: parameters, lightTexture: atlas)
        try Task.checkCancellation()
        logger.notice("load stage=program elapsed=\(String(describing: started.duration(to: .now)), privacy: .public)")
        logger.notice("Runtime parameter textures: \(parameters.textureBytes) bytes")
        let runtime = try TidalEnvironmentRuntime(root: root, template: darkTemplate, darkTextures: darkTextures)
        try await runtime.prewarm()
        try Task.checkCancellation()
        TidalMotionSystem.registerSystem()
        root.components.set(TidalRuntimeComponent(runtime: runtime))
        root.disableEnvironmentPreviewScreen()
        update(nil, in: root)
        restPose = pose
        return root
    }

    public func apply(_ appearance: EnvironmentAppearance, to root: Entity) {
        root.components[TidalRuntimeComponent.self]?.runtime.request(appearance)
    }

    public func update(_ screen: EnvironmentScreenState?, in root: Entity) {
        if let screen { root.alignDockingRegion(to: screen) }
        root.components[TidalRuntimeComponent.self]?.runtime.updateScreen(screen, in: root)
    }
}
