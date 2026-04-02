import RealityKit
import UIKit

enum VirtualScreenEntity {

    static func makeEntity(
        textureResource: TextureResource?,
        geometry: SpatialSceneDomain.ScreenGeometry = .flat(width: 2.4, height: 1.35)
    ) -> Entity {
        let entity = Entity()
        entity.components.set(
            ModelComponent(
                mesh: mesh(for: geometry),
                materials: [material(textureResource: textureResource)]
            )
        )
        entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
        entity.components.set(CollisionComponent(shapes: [.generateBox(width: 3.0, height: 2.0, depth: 0.1)]))
        applyNormalFlip(to: entity, geometry: geometry)
        entity.position = SIMD3<Float>(0, 0, -8)
        return entity
    }

    static func updateTexture(
        on entity: Entity,
        textureResource: TextureResource
    ) {
        guard var model = entity.components[ModelComponent.self] else { return }
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        mat.color = .init(tint: .white, texture: .init(textureResource))
        model.materials = [mat]
        entity.components.set(model)
    }

    static func switchGeometry(
        on entity: Entity,
        to geometry: SpatialSceneDomain.ScreenGeometry,
        textureResource: TextureResource?
    ) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.mesh = mesh(for: geometry)
        model.materials = [material(textureResource: textureResource)]
        entity.components.set(model)
        // Reset before re-applying so toggling curved→flat→curved stays correct.
        entity.scale.x = abs(entity.scale.x)
        applyNormalFlip(to: entity, geometry: geometry)
    }

    static func updatePosition(
        on entity: Entity,
        distance: Float,
        verticalOffset: Float,
        viewAngle: Float
    ) {
        entity.position = SIMD3<Float>(0, verticalOffset, -distance)
        entity.orientation = simd_quatf(
            angle: viewAngle * .pi / 180,
            axis: SIMD3<Float>(1, 0, 0)
        )
    }
}

// MARK: - Private helpers

private extension VirtualScreenEntity {

    static func mesh(for geometry: SpatialSceneDomain.ScreenGeometry) -> MeshResource {
        switch geometry {
        case .flat(let w, let h):
            return MeshResource.generatePlane(width: w, height: h)
        case .curved(let r, let h):
            return MeshResource.generateCylinder(height: h, radius: r)
        }
    }

    static func material(textureResource: TextureResource?) -> UnlitMaterial {
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        if let textureResource {
            mat.color = .init(tint: .white, texture: .init(textureResource))
        }
        return mat
    }

    /// Curved surfaces need normals pointing inward for inside-surface rendering.
    /// Flat planes face +Z by default, so no flip is needed.
    static func applyNormalFlip(to entity: Entity, geometry: SpatialSceneDomain.ScreenGeometry) {
        switch geometry {
        case .flat:
            break
        case .curved:
            entity.scale.x *= -1
        }
    }
}
