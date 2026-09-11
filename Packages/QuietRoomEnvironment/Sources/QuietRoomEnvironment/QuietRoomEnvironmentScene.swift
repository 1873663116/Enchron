import EnvironmentSceneContract
import Foundation
import RealityKit
import simd

public final class QuietRoomEnvironmentScene: EnvironmentScene {
    public static let resourceName = "quiet_room"
    public static let screenCenterParameter = "screen_center"
    public static let screenHalfWidthParameter = "screen_half_width"
    public static let screenHalfHeightParameter = "screen_half_height"
    public static let screenVideoColorParameter = "screen_video_color"
    public static let screenLightGainParameter = "screen_light_gain"

    public nonisolated static let descriptor = EnvironmentSceneDescriptor(
        identifier: "quiet-room",
        geometry: EnvironmentSceneGeometry(
            ceilingHeightMeters: 6.0,
            ceilingClearanceMeters: 0.05,
            distanceStrategy: .movesViewer,
            defaultDistanceMeters: 12,
            distanceRangeMeters: 6...15.5,
            defaultScreenHeightMeters: 4.5,
            screenHeightRangeMeters: 2...5.5,
            elevationRangeDegrees: 0...90,
            screenRestHeightMeters: nil
        ),
        supportsDarkAppearance: false
    )

    private struct GlowSurface {
        let entity: Entity
        let materialIndex: Int
        let authoredLightGain: Float
    }

    private var glowSurfaces: [GlowSurface] = []

    public init() {}

    public var descriptor: EnvironmentSceneDescriptor { Self.descriptor }

    public func load() async throws -> Entity {
        guard let url = Bundle.module.url(forResource: Self.resourceName, withExtension: "reality") else {
            throw EnvironmentSceneLoadingError.resourceMissing(Self.resourceName)
        }
        let root = try await Entity(contentsOf: url)
        guard root.findEntity(named: EnvironmentSceneEntityName.playbackSurfaceAnchor) != nil else {
            throw EnvironmentSceneLoadingError.entityMissing(EnvironmentSceneEntityName.playbackSurfaceAnchor)
        }
        root.disableEnvironmentPreviewScreen()
        glowSurfaces = Self.collectGlowSurfaces(in: root)
        return root
    }

    public func apply(_ appearance: EnvironmentAppearance, to root: Entity) {}

    public func update(_ screen: EnvironmentScreenState?, in root: Entity) {
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
                try? material.setParameter(name: Self.screenLightGainParameter, value: .float(surface.authoredLightGain))
                if let texture = screen.videoTexture {
                    try? material.setParameter(name: Self.screenVideoColorParameter, value: .textureResource(texture))
                }
            } else {
                try? material.setParameter(name: Self.screenLightGainParameter, value: .float(0))
            }
            model.materials[surface.materialIndex] = material
            surface.entity.components.set(model)
        }
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
                    surfaces.append(GlowSurface(entity: entity, materialIndex: index, authoredLightGain: gain))
                }
            }
            for child in entity.children { visit(child) }
        }
        visit(root)
        return surfaces
    }
}
