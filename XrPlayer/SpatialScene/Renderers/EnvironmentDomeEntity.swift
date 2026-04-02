import RealityKit
import UIKit

/// Sky dome entity for cinema immersive environments.
/// Renders a large inverted sphere with environment-specific material.
/// When an environment defines a `skyboxAssetName`, the dome loads and
/// displays that texture; otherwise it falls back to a solid colour.
/// One dome is shared across all environments — switch via material replacement.
enum EnvironmentDomeEntity {

    static let domeRadius: Float = 50.0

    /// Creates a dome entity with a solid fallback colour.
    /// Call `loadSkyboxTexture(on:environment:)` afterwards to apply the
    /// skybox texture asynchronously.
    static func makeEntity(
        environment: SpatialSceneDomain.CinemaEnvironment
    ) -> Entity {
        let mesh = MeshResource.generateSphere(radius: domeRadius)
        let entity = Entity()
        entity.components.set(
            ModelComponent(
                mesh: mesh,
                materials: [colorMaterial(for: environment)]
            )
        )
        entity.scale.x *= -1  // Invert normals → render on inside
        return entity
    }

    /// Loads the skybox texture for `environment` and applies it to the
    /// dome entity's material. No-op if the environment has no texture asset.
    /// Falls back to solid colour on load failure.
    static func loadSkyboxTexture(
        on entity: Entity,
        environment: SpatialSceneDomain.CinemaEnvironment
    ) async {
        guard let assetName = environment.skyboxAssetName else { return }
        do {
            let resource = try await TextureResource(named: assetName)
            var mat = UnlitMaterial(applyPostProcessToneMap: false)
            mat.color = .init(tint: .white, texture: .init(resource))
            guard var model = entity.components[ModelComponent.self] else { return }
            model.materials = [mat]
            entity.components.set(model)
        } catch {
            print("[EnvironmentDome] texture_load_failed name=\(assetName) error=\(error)")
        }
    }

    /// Switches the dome to a new environment: applies the fallback colour
    /// immediately, then loads the skybox texture asynchronously.
    static func switchEnvironment(
        on entity: Entity,
        to environment: SpatialSceneDomain.CinemaEnvironment
    ) async {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = [colorMaterial(for: environment)]
        entity.components.set(model)
        await loadSkyboxTexture(on: entity, environment: environment)
    }
}

private extension EnvironmentDomeEntity {

    static func colorMaterial(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> UnlitMaterial {
        var mat = UnlitMaterial(applyPostProcessToneMap: false)
        mat.color = .init(tint: color(for: environment))
        return mat
    }

    static func color(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> UIColor {
        switch environment {
        case .darkTheatre:
            return UIColor(white: 0.02, alpha: 1.0)
        case .starryNight:
            return UIColor(red: 0.01, green: 0.01, blue: 0.06, alpha: 1.0)
        case .sunsetNature:
            return UIColor(red: 0.15, green: 0.08, blue: 0.03, alpha: 1.0)
        }
    }
}
