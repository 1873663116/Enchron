import Foundation

public struct PlaybackSurfaceTransform: Equatable, Sendable {
    public let distance: Double
    public let elevationDegrees: Double
    public let scale: Double

    public init(distance: Double, elevationDegrees: Double, scale: Double) {
        self.distance = distance
        self.elevationDegrees = elevationDegrees
        self.scale = scale
    }
}

public struct MacWindowPlaybackCameraGeometry: Equatable, Sendable {
    nonisolated public static let fieldOfViewInDegrees: Float = 50
    nonisolated public static let fillFraction: Float = 0.98

    nonisolated public let screenSize: SIMD2<Float>
    nonisolated public let distance: Float

    nonisolated public static func resolve(
        screenSize: SIMD2<Float>,
        canvasSize: CGSize
    ) -> Self {
        let resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : SIMD2<Float>(16.0 / 9.0, 1)
        let canvasAspect = max(Float(canvasSize.width), 1)
            / max(Float(canvasSize.height), 1)
        let verticalTangent = tan(fieldOfViewInDegrees * .pi / 360)
        let verticalDistance = resolvedScreenSize.y / 2 / verticalTangent
        let horizontalDistance = resolvedScreenSize.x / 2 / (verticalTangent * canvasAspect)

        return Self(
            screenSize: resolvedScreenSize,
            distance: max(verticalDistance, horizontalDistance) / fillFraction
        )
    }
}
