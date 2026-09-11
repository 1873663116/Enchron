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
    public var screenRestHeightMeters: Float?

    public init(
        ceilingHeightMeters: Float? = nil,
        ceilingClearanceMeters: Float = 0.05,
        distanceStrategy: EnvironmentDistanceStrategy = .movesScreen,
        defaultDistanceMeters: Double = 12,
        distanceRangeMeters: ClosedRange<Double> = 6...30,
        defaultScreenHeightMeters: Double = 4.5,
        screenHeightRangeMeters: ClosedRange<Double> = 2...6,
        elevationRangeDegrees: ClosedRange<Double> = 0...90,
        screenRestHeightMeters: Float? = nil
    ) {
        self.ceilingHeightMeters = ceilingHeightMeters
        self.ceilingClearanceMeters = ceilingClearanceMeters
        self.distanceStrategy = distanceStrategy
        self.defaultDistanceMeters = defaultDistanceMeters
        self.distanceRangeMeters = distanceRangeMeters
        self.defaultScreenHeightMeters = defaultScreenHeightMeters
        self.screenHeightRangeMeters = screenHeightRangeMeters
        self.elevationRangeDegrees = elevationRangeDegrees
        self.screenRestHeightMeters = screenRestHeightMeters
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
    public static let playbackSurfaceAnchor = "PlaybackSurfaceAnchor"
    public static let screenPreview = "ScreenPreview"
}

public protocol EnvironmentScene: AnyObject {
    var descriptor: EnvironmentSceneDescriptor { get }
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
