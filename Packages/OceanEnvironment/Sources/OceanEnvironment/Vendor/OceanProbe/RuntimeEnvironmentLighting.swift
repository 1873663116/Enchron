import Foundation
import RealityKit

enum RuntimeEnvironmentLightingError: LocalizedError {
    case environmentImageUnavailable

    var errorDescription: String? {
        switch self {
        case .environmentImageUnavailable:
            "The procedural sky environment image could not be created."
        }
    }
}

/// Lights the ocean from the authored procedural sky.
///
/// The environment is synthesized from `SkyAppearance` rather than decoded from
/// an HDRI, so the scene carries no environment texture: the equirect is rebuilt
/// only when the authored sky parameters change.
@MainActor
enum RuntimeEnvironmentLighting {
    static let lightEntityName = "OceanEnvironmentLight"
    static let environmentName = "OceanProceduralSky"

    private static var cachedEnvironment: EnvironmentResource?
    private static var cachedAppearance: SkyAppearance?

    struct SynchronizationResult {
        let rebuiltEnvironment: Bool
        let createdLight: Bool
        let changedIntensity: Bool
    }

    /// Kept so the application runtime can announce itself without owning a
    /// texture bundle any more.
    static func configure(applicationResourceBundle: Bundle) {}

    static func synchronize(
        surface: Entity,
        to oceanEntity: Entity,
        sky: SkyAppearance,
        intensityExponent: Float
    ) throws -> SynchronizationResult {
        let rebuilt = cachedAppearance != sky || cachedEnvironment == nil
        let environment = try environmentResource(for: sky)

        let light: Entity
        let createdLight: Bool
        if let existingLight = oceanEntity.findEntity(named: lightEntityName) {
            light = existingLight
            createdLight = false
        } else {
            light = Entity()
            light.name = lightEntityName
            oceanEntity.addChild(light)
            createdLight = true
        }

        var lightComponent = light.components[ImageBasedLightComponent.self]
            ?? ImageBasedLightComponent(source: .single(environment))
        let changedIntensity = lightComponent.intensityExponent != intensityExponent
        lightComponent.source = .single(environment)
        lightComponent.intensityExponent = intensityExponent
        lightComponent.inheritsRotation = true
        light.components.set(lightComponent)
        surface.components.set(
            ImageBasedLightReceiverComponent(imageBasedLight: light)
        )
        return SynchronizationResult(
            rebuiltEnvironment: rebuilt,
            createdLight: createdLight,
            changedIntensity: changedIntensity
        )
    }

    private static func environmentResource(for sky: SkyAppearance) throws -> EnvironmentResource {
        if let cachedEnvironment, cachedAppearance == sky {
            return cachedEnvironment
        }
        guard let image = sky.makeEquirectangularImage() else {
            throw RuntimeEnvironmentLightingError.environmentImageUnavailable
        }
        let environment = try EnvironmentResource(
            equirectangular: image,
            withName: environmentName
        )
        cachedEnvironment = environment
        cachedAppearance = sky
        return environment
    }
}
