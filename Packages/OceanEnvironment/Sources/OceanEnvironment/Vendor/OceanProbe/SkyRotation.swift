import RealityKit
import simd

/// Turns the sky.
///
/// The dome and the key light rotate together about world Y at one shared
/// rate, so the HDRI's own sun stays where the light says it is. The rotation
/// is applied to each entity's *authored* orientation rather than accumulated
/// onto its current one, so the scene at t = 0 is exactly the scene as saved
/// and no error builds up over an hour of drift.
///
/// The cloud layer in `OceanSky` is addressed from the world-space view ray
/// and so does not turn with the dome — it moves only by its own wind. That
/// difference in angular rate between the two layers is what reads as depth;
/// see `scripts/author_sky_graph.py`.
public struct SkyRotationComponent: Component {
    /// Radians per second about world Y. Positive turns the sky eastward.
    public var rate: Double
    /// The orientation the scene was authored with, captured when installed.
    public var base: simd_quatf
    /// Seconds since the space opened, accumulated in double precision so a
    /// multi-hour session does not quantize the angle.
    public var elapsed: Double = 0

    public init(rate: Double, base: simd_quatf) {
        self.rate = rate
        self.base = base
    }
}

public struct SkyRotationSystem: System {
    private static let query = EntityQuery(where: .has(SkyRotationComponent.self))

    public init(scene: RealityKit.Scene) {}

    public func update(context: SceneUpdateContext) {
        for entity in context.entities(
            matching: Self.query,
            updatingSystemWhen: .rendering
        ) {
            guard var rotation = entity.components[SkyRotationComponent.self] else { continue }
            rotation.elapsed += context.deltaTime
            entity.components[SkyRotationComponent.self] = rotation

            let angle = Float(rotation.rate * rotation.elapsed)
            let turn = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
            entity.orientation = turn * rotation.base
        }
    }
}

public enum SkyRotation {
    /// One turn in forty minutes: slow enough that no single glance reads as
    /// motion, fast enough that the sky is visibly elsewhere after a while.
    public static let defaultPeriod: Double = 40 * 60

    /// Entities that make up the sky. The dome carries the HDRI on its own
    /// UVs, so turning the dome turns the sky; the light has to follow or the
    /// water's highlight drifts away from the sun in the image.
    public static let turningEntities = ["OceanSkyDome", "OceanSoftLight"]

    @discardableResult
    @MainActor
    public static func install(in root: Entity, period: Double = defaultPeriod) -> Int {
        SkyRotationSystem.registerSystem()
        let rate = (2 * Double.pi) / period
        var installed = 0
        for name in turningEntities {
            guard let entity = root.findEntity(named: name) else { continue }
            entity.components.set(
                SkyRotationComponent(rate: rate, base: entity.orientation)
            )
            installed += 1
        }
        return installed
    }
}
