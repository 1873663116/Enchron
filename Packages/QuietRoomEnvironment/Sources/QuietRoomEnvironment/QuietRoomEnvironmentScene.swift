import EnvironmentSceneContract
import Foundation
import RealityKit
import simd

public final class QuietRoomEnvironmentScene: EnvironmentScene {
    public static let resourceName = "quiet_room"
    public static let screenCenterParameter = "screen_center"
    public static let screenHalfWidthParameter = "screen_half_width"
    public static let screenHalfHeightParameter = "screen_half_height"
    public static let screenForwardParameter = "screen_forward"
    public static let screenVideoColorParameter = "screen_video_color"
    public static let screenLightGainParameter = "screen_light_gain"
    public static let screenLodNearParameter = "screen_lod_near"
    public static let screenLodFarParameter = "screen_lod_far"
    public static let authoredVideoWidth: Float = 1920
    public static let tileNamePrefixes = ["Floor_", "Ceil_"]
    public static let instancedTilesNamePrefix = "QuietRoomTiles"

    public nonisolated static let descriptor = EnvironmentSceneDescriptor(
        identifier: "quiet-room",
        geometry: EnvironmentSceneGeometry(
            ceilingHeightMeters: 7.75,
            ceilingClearanceMeters: 0.05,
            distanceStrategy: .movesViewer,
            defaultDistanceMeters: 8,
            distanceRangeMeters: 5...18,
            defaultScreenHeightMeters: 8,
            screenHeightRangeMeters: 8...8,
            defaultViewerHeightMeters: 1.5,
            viewerHeightRangeMeters: -1...3,
            elevationRangeDegrees: 0...90
        ),
        supportsDarkAppearance: false
    )

    private struct GlowSurface {
        let entity: Entity
        let materialIndex: Int
        let authoredLightGain: Float
        let authoredLodNear: Float
        let authoredLodFar: Float
    }

    private struct TileGroupKey: Hashable {
        let kind: String
        let variant: String
    }

    private struct TileMember {
        let entity: Entity
        let model: ModelComponent
        let matrix: simd_float4x4
    }

    private var glowSurfaces: [GlowSurface] = []

    public private(set) var restPose: EnvironmentScreenRestPose?
    public private(set) var instancedTileCount = 0
    public private(set) var instancedTileGroupCount = 0

    public init() {}

    public var descriptor: EnvironmentSceneDescriptor { Self.descriptor }

    public func load() async throws -> Entity {
        guard let url = Bundle.module.url(forResource: Self.resourceName, withExtension: "reality") else {
            throw EnvironmentSceneLoadingError.resourceMissing(Self.resourceName)
        }
        let root = try await Entity(contentsOf: url)
        guard let pose = EnvironmentScreenRestPose.dockingRegion(
            in: root,
            screenHeight: Float(Self.descriptor.geometry.defaultScreenHeightMeters)
        ) else {
            throw EnvironmentSceneLoadingError.entityMissing(EnvironmentSceneEntityName.dockingRegion)
        }
        restPose = pose
        root.disableEnvironmentPreviewScreen()
        let instancing = Self.instanceTiles(in: root)
        instancedTileCount = instancing.tiles
        instancedTileGroupCount = instancing.groups
        glowSurfaces = Self.collectGlowSurfaces(in: root)
        return root
    }

    public func apply(_ appearance: EnvironmentAppearance, to root: Entity) {}

    public func update(_ screen: EnvironmentScreenState?, in root: Entity) {
        if let screen {
            root.alignDockingRegion(to: screen)
        }
        for surface in glowSurfaces {
            guard var model = surface.entity.components[ModelComponent.self],
                  surface.materialIndex < model.materials.count,
                  var material = model.materials[surface.materialIndex] as? ShaderGraphMaterial else {
                continue
            }
            if let screen {
                try? material.setParameter(name: Self.screenCenterParameter, value: .simd3Float(screen.center))
                try? material.setParameter(name: Self.screenHalfWidthParameter, value: .float(screen.halfWidth))
                try? material.setParameter(name: Self.screenHalfHeightParameter, value: .float(screen.halfHeight))
                try? material.setParameter(name: Self.screenForwardParameter, value: .simd3Float(screen.normal))
                try? material.setParameter(name: Self.screenLightGainParameter, value: .float(surface.authoredLightGain))
                if let texture = screen.videoTexture {
                    let bias = log2(Self.authoredVideoWidth / Float(max(texture.width, 1)))
                    try? material.setParameter(name: Self.screenLodNearParameter, value: .float(max(surface.authoredLodNear - bias, 0)))
                    try? material.setParameter(name: Self.screenLodFarParameter, value: .float(max(surface.authoredLodFar - bias, 0)))
                    try? material.setParameter(name: Self.screenVideoColorParameter, value: .textureResource(texture))
                }
            } else {
                try? material.setParameter(name: Self.screenLightGainParameter, value: .float(0))
            }
            model.materials[surface.materialIndex] = material
            surface.entity.components.set(model)
        }
    }

    private static func tileKey(for name: String) -> TileGroupKey? {
        guard tileNamePrefixes.contains(where: { name.hasPrefix($0) }),
              let first = name.firstIndex(of: "_"),
              let last = name.lastIndex(of: "_"),
              first < last else {
            return nil
        }
        return TileGroupKey(kind: String(name[..<first]), variant: String(name[name.index(after: last)...]))
    }

    private static func firstModelEntity(in entity: Entity) -> Entity? {
        if entity.components.has(ModelComponent.self) { return entity }
        for child in entity.children {
            if let found = firstModelEntity(in: child) { return found }
        }
        return nil
    }

    private static func matrix(of entity: Entity, upTo root: Entity) -> simd_float4x4 {
        var matrix = entity.transform.matrix
        var current = entity
        while current !== root, let parent = current.parent, parent !== root {
            matrix = parent.transform.matrix * matrix
            current = parent
        }
        return matrix
    }

    private static func instanceTiles(in root: Entity) -> (tiles: Int, groups: Int) {
        var tiles: [Entity] = []
        func visit(_ entity: Entity) {
            if tileKey(for: entity.name) != nil {
                tiles.append(entity)
                return
            }
            for child in entity.children { visit(child) }
        }
        visit(root)
        var members: [TileGroupKey: [TileMember]] = [:]
        var order: [TileGroupKey] = []
        for tile in tiles {
            guard let key = tileKey(for: tile.name),
                  let modelEntity = firstModelEntity(in: tile),
                  let model = modelEntity.components[ModelComponent.self] else {
                continue
            }
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(
                TileMember(entity: tile, model: model, matrix: matrix(of: modelEntity, upTo: root))
            )
        }
        var instanced = 0
        var groups = 0
        for key in order {
            guard let group = members[key], let first = group.first else { continue }
            do {
                let data = try LowLevelInstanceData(instanceCount: group.count)
                data.withMutableTransforms { transforms in
                    for (index, member) in group.enumerated() {
                        transforms[index] = member.matrix
                    }
                }
                let component = try MeshInstancesComponent(
                    mesh: first.model.mesh,
                    modelID: first.model.mesh.contents.models.first?.id,
                    instances: data
                )
                let host = Entity()
                host.name = "\(instancedTilesNamePrefix)_\(key.kind)_\(key.variant)"
                host.components.set(first.model)
                host.components.set(component)
                root.addChild(host)
                for member in group { member.entity.removeFromParent() }
                instanced += group.count
                groups += 1
            } catch {
                continue
            }
        }
        return (instanced, groups)
    }

    private static func authoredFloat(_ graph: ShaderGraphMaterial, _ name: String, fallback: Float) -> Float {
        if case .float(let value)? = graph.getParameter(name: name) {
            return value
        }
        return fallback
    }

    private static func collectGlowSurfaces(in root: Entity) -> [GlowSurface] {
        var surfaces: [GlowSurface] = []
        func visit(_ entity: Entity) {
            if let model = entity.components[ModelComponent.self] {
                for (index, material) in model.materials.enumerated() {
                    guard let graph = material as? ShaderGraphMaterial,
                          graph.parameterNames.contains(screenCenterParameter) else { continue }
                    let gain: Float
                    if case .float(let value)? = graph.getParameter(name: screenLightGainParameter) {
                        gain = value
                    } else {
                        gain = 1
                    }
                    surfaces.append(GlowSurface(
                        entity: entity,
                        materialIndex: index,
                        authoredLightGain: gain,
                        authoredLodNear: authoredFloat(graph, screenLodNearParameter, fallback: 6),
                        authoredLodFar: authoredFloat(graph, screenLodFarParameter, fallback: 7)
                    ))
                }
            }
            for child in entity.children { visit(child) }
        }
        visit(root)
        return surfaces
    }
}
