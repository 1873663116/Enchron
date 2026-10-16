import RealityKit
import simd

public struct SkyRotationComponent: Component {
    public var rate: Double
    public var base: simd_quatf
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
    public static let defaultPeriod: Double = 40 * 60

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
