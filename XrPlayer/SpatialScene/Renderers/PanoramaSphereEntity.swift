import RealityKit
import UIKit

/// Creates a sphere entity whose normals are flipped inward so that a
/// video texture renders on the *inside* surface — the standard approach
/// for equirectangular 360 / 180 panorama playback.
///
/// The material uses `UnlitMaterial` with `applyPostProcessToneMap: false`
/// because the video frames have already been colour-processed by mpv;
/// RealityKit must not apply additional tone mapping.
enum PanoramaSphereEntity {

    /// Sphere radius in metres. 10 m gives comfortable viewing distance
    /// in a visionOS ImmersiveSpace.
    static let defaultRadius: Float = 10.0

    /// Creates a sphere entity ready for panorama video display.
    ///
    /// - Parameter textureResource: The `TextureResource` exposed by the
    ///   active panorama bridge. Pass `nil` to create the entity without
    ///   a texture during bridge startup.
    /// - Returns: A configured `Entity` with an inverted sphere mesh.
    static func makeEntity(
        textureResource: TextureResource?,
        radius: Float = defaultRadius
    ) -> Entity {
        let mesh = MeshResource.generateSphere(radius: radius)

        var material = UnlitMaterial(applyPostProcessToneMap: false)
        if let textureResource {
            material.color = .init(
                tint: .white,
                texture: .init(textureResource)
            )
        }

        let entity = Entity()
        entity.components.set(ModelComponent(mesh: mesh, materials: [material]))

        // Flip X scale to invert normals → texture renders on the inside.
        entity.scale.x *= -1

        return entity
    }

    /// Updates the material's base-colour texture on an existing sphere
    /// entity when the panorama bridge publishes a new texture resource.
    static func updateTexture(
        on entity: Entity,
        textureResource: TextureResource
    ) {
        guard var model = entity.components[ModelComponent.self] else { return }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(
            tint: .white,
            texture: .init(textureResource)
        )
        model.materials = [material]
        entity.components.set(model)
    }
}
