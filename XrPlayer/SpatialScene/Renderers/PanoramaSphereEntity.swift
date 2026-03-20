import RealityKit
import UIKit

/// Projection style that determines the sphere mesh geometry.
/// 360° uses a full sphere; 180° uses the front hemisphere only.
enum PanoramaProjection {
    case full360
    case front180
}

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
    /// - Parameters:
    ///   - textureResource: The `TextureResource` exposed by the active
    ///     panorama bridge. Pass `nil` to create the entity without a
    ///     texture during bridge startup.
    ///   - projection: `.full360` for equirectangular 360° content,
    ///     `.front180` for 180° content (front hemisphere only).
    ///     Defaults to `.full360`.
    /// - Returns: A configured `Entity` with an inverted sphere mesh.
    static func makeEntity(
        textureResource: TextureResource?,
        projection: PanoramaProjection = .full360,
        radius: Float = defaultRadius
    ) -> Entity {
        // RealityKit's generateSphere always produces a full sphere.
        // For 180° we still use the full sphere but clip via texture
        // coordinates in a future iteration. The API is ready for it.
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
