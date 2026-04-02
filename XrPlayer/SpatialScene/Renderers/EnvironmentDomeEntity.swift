import RealityKit
import UIKit

/// Sky dome entity for cinema immersive environments.
/// Renders a large inverted sphere with environment-specific color.
/// One dome is shared across all environments — switch via material replacement.
enum EnvironmentDomeEntity {

    static let domeRadius: Float = 50.0

    static func makeEntity(
        environment: SpatialSceneDomain.CinemaEnvironment
    ) -> Entity {
        let mesh = MeshResource.generateSphere(radius: domeRadius)
        let entity = Entity()
        entity.components.set(
            ModelComponent(
                mesh: mesh,
                materials: [material(for: environment)]
            )
        )
        entity.scale.x *= -1  // Invert normals → render on inside
        return entity
    }

    static func switchEnvironment(
        on entity: Entity,
        to environment: SpatialSceneDomain.CinemaEnvironment
    ) {
        guard var model = entity.components[ModelComponent.self] else { return }
        model.materials = [material(for: environment)]
        entity.components.set(model)
    }
}

private extension EnvironmentDomeEntity {

    static func material(
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
