import Foundation

public enum WindowPlaybackSurfaceGeometry {
    nonisolated public static let unitHeight: Float = 1
    nonisolated public static let defaultSurfaceSize =
        SIMD2<Float>(16.0 / 9.0, unitHeight)
    nonisolated public static let flatDepth: CGFloat = 0
    nonisolated public static let backgroundSortOrder: Int32 = 0

    nonisolated public static func uniformScale(
        surfaceSize: SIMD2<Float>,
        availableSize: SIMD2<Float>
    ) -> Float? {
        guard surfaceSize.x > 0,
              surfaceSize.y > 0,
              availableSize.x > 0,
              availableSize.y > 0 else {
            return nil
        }
        let scale = min(
            availableSize.x / surfaceSize.x,
            availableSize.y / surfaceSize.y
        )
        return scale.isFinite && scale > 0 ? scale : nil
    }

    nonisolated public static func layout(
        surfaceSize: SIMD2<Float>,
        sceneCenter: SIMD3<Float>,
        sceneExtents: SIMD3<Float>
    ) -> WindowPlaybackSurfaceLayout? {
        let availableSize = SIMD2<Float>(
            abs(sceneExtents.x),
            abs(sceneExtents.y)
        )
        guard let scale = uniformScale(
            surfaceSize: surfaceSize,
            availableSize: availableSize
        ) else {
            return nil
        }
        return WindowPlaybackSurfaceLayout(
            sceneCenter: sceneCenter,
            availableSize: availableSize,
            scale: scale,
            renderedSize: surfaceSize * scale
        )
    }
}

public struct WindowPlaybackSurfaceLayout: Equatable, Sendable {
    public let sceneCenter: SIMD3<Float>
    public let availableSize: SIMD2<Float>
    public let scale: Float
    public let renderedSize: SIMD2<Float>

    nonisolated public init(
        sceneCenter: SIMD3<Float>,
        availableSize: SIMD2<Float>,
        scale: Float,
        renderedSize: SIMD2<Float>
    ) {
        self.sceneCenter = sceneCenter
        self.availableSize = availableSize
        self.scale = scale
        self.renderedSize = renderedSize
    }
}

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
    nonisolated public static let safeFillFraction: Float = 0.98

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
            distance: max(verticalDistance, horizontalDistance)
                / safeFillFraction
        )
    }
}
