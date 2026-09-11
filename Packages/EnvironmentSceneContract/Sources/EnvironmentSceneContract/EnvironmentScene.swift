import RealityKit
import simd

public nonisolated enum EnvironmentDistanceStrategy: String, Sendable, Equatable, Codable {
    case movesScreen
    case movesViewer
}

public nonisolated struct EnvironmentSceneGeometry: Sendable, Equatable {
    public var ceilingHeightMeters: Float?
    public var ceilingClearanceMeters: Float
    public var distanceStrategy: EnvironmentDistanceStrategy
    public var defaultDistanceMeters: Double
    public var distanceRangeMeters: ClosedRange<Double>
    public var defaultScreenHeightMeters: Double
    public var screenHeightRangeMeters: ClosedRange<Double>
    public var elevationRangeDegrees: ClosedRange<Double>

    public init(
        ceilingHeightMeters: Float? = nil,
        ceilingClearanceMeters: Float = 0.05,
        distanceStrategy: EnvironmentDistanceStrategy = .movesScreen,
        defaultDistanceMeters: Double = 12,
        distanceRangeMeters: ClosedRange<Double> = 6...30,
        defaultScreenHeightMeters: Double = 4.5,
        screenHeightRangeMeters: ClosedRange<Double> = 2...6,
        elevationRangeDegrees: ClosedRange<Double> = 0...90
    ) {
        self.ceilingHeightMeters = ceilingHeightMeters
        self.ceilingClearanceMeters = ceilingClearanceMeters
        self.distanceStrategy = distanceStrategy
        self.defaultDistanceMeters = defaultDistanceMeters
        self.distanceRangeMeters = distanceRangeMeters
        self.defaultScreenHeightMeters = defaultScreenHeightMeters
        self.screenHeightRangeMeters = screenHeightRangeMeters
        self.elevationRangeDegrees = elevationRangeDegrees
    }
}

public nonisolated struct EnvironmentScreenRestPose: Sendable, Equatable {
    public var center: SIMD3<Float>
    public var right: SIMD3<Float>
    public var up: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var halfWidth: Float
    public var halfHeight: Float

    public init(
        center: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>,
        normal: SIMD3<Float>,
        halfWidth: Float,
        halfHeight: Float
    ) {
        self.center = center
        self.right = right
        self.up = up
        self.normal = normal
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
    }

    public var bottomHeight: Float {
        center.y - halfHeight
    }

    public var distance: Float {
        simd_length(SIMD2<Float>(center.x, center.z))
    }

    public var yawRadians: Float {
        atan2(-center.x, -center.z)
    }

    public var screenHeight: Float {
        2 * halfHeight
    }

    public var screenWidth: Float {
        2 * halfWidth
    }

    public init(screenPreviewWorldTransform matrix: simd_float4x4) {
        let axisX = SIMD3<Float>(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        let axisY = SIMD3<Float>(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        let axisZ = SIMD3<Float>(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        let center = SIMD3<Float>(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
        var normal = simd_normalize(axisY)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let projected = worldUp - simd_dot(worldUp, normal) * normal
        let up: SIMD3<Float>
        if simd_length(projected) > 1e-4 {
            up = simd_normalize(projected)
        } else {
            let alternate = axisZ - simd_dot(axisZ, normal) * normal
            up = simd_length(alternate) > 1e-4
                ? simd_normalize(alternate)
                : SIMD3<Float>(0, 0, 1)
        }
        var right = simd_cross(up, normal)
        if simd_dot(normal, -center) < 0 {
            normal = -normal
            right = -right
        }
        self.init(
            center: center,
            right: right,
            up: up,
            normal: normal,
            halfWidth: 0.5 * (abs(simd_dot(axisX, right)) + abs(simd_dot(axisZ, right))),
            halfHeight: 0.5 * (abs(simd_dot(axisX, up)) + abs(simd_dot(axisZ, up)))
        )
    }

    public static func screenPreview(in root: Entity) -> EnvironmentScreenRestPose? {
        guard let preview = root.findEntity(named: EnvironmentSceneEntityName.screenPreview) else {
            return nil
        }
        return EnvironmentScreenRestPose(
            screenPreviewWorldTransform: worldTransform(of: preview, upTo: root)
        )
    }

    private static func worldTransform(of entity: Entity, upTo root: Entity) -> simd_float4x4 {
        var matrix = entity.transform.matrix
        var current = entity
        while current !== root, let parent = current.parent {
            matrix = parent.transform.matrix * matrix
            current = parent
        }
        return matrix
    }
}

public nonisolated struct EnvironmentSceneDescriptor: Sendable, Equatable {
    public var identifier: String
    public var geometry: EnvironmentSceneGeometry
    public var supportsDarkAppearance: Bool

    public init(
        identifier: String,
        geometry: EnvironmentSceneGeometry,
        supportsDarkAppearance: Bool
    ) {
        self.identifier = identifier
        self.geometry = geometry
        self.supportsDarkAppearance = supportsDarkAppearance
    }
}

public nonisolated struct EnvironmentAppearance: Sendable, Equatable {
    public static let light = EnvironmentAppearance(brightness: 1)
    public static let dark = EnvironmentAppearance(brightness: 0.5)

    public var brightness: Float

    public init(brightness: Float) {
        self.brightness = brightness
    }
}

public struct EnvironmentScreenState {
    public var center: SIMD3<Float>
    public var right: SIMD3<Float>
    public var up: SIMD3<Float>
    public var halfWidth: Float
    public var halfHeight: Float
    public var videoTexture: TextureResource?

    public init(
        center: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>,
        halfWidth: Float,
        halfHeight: Float,
        videoTexture: TextureResource? = nil
    ) {
        self.center = center
        self.right = right
        self.up = up
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.videoTexture = videoTexture
    }

    public var normal: SIMD3<Float> {
        simd_normalize(simd_cross(right, up))
    }
}

public nonisolated enum EnvironmentSceneEntityName {
    public static let screenPreview = "ScreenPreview"
}

public protocol EnvironmentScene: AnyObject {
    var descriptor: EnvironmentSceneDescriptor { get }
    var restPose: EnvironmentScreenRestPose? { get }
    func load() async throws -> Entity
    func apply(_ appearance: EnvironmentAppearance, to root: Entity)
    func update(_ screen: EnvironmentScreenState?, in root: Entity)
}

public enum EnvironmentSceneLoadingError: Error, Equatable {
    case resourceMissing(String)
    case entityMissing(String)
}

extension Entity {
    public func disableEnvironmentPreviewScreen() {
        findEntity(named: EnvironmentSceneEntityName.screenPreview)?.isEnabled = false
    }
}
