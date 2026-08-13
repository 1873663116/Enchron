import Foundation

public enum WindowPlaybackSurfaceGeometry {
    nonisolated public static let unitHeight: Float = 1
    nonisolated public static let defaultSurfaceSize =
        SIMD2<Float>(16.0 / 9.0, unitHeight)
    nonisolated public static let flatWindowDepth: CGFloat = 0
    /// Projected Portal video needs spatial extent inside its Window scene.
    /// The value is in SwiftUI scene units and matches Apple's immersive-media
    /// PlayerWindow contract; a zero-depth host can leave the component loading.
    nonisolated public static let projectedPortalDepth: CGFloat = 1
    nonisolated public static let backgroundSortOrder: Int32 = 0

    nonisolated public static func realityViewDepth(
        for presentation: PlaybackPresentation
    ) -> CGFloat {
        presentation == .portal ? projectedPortalDepth : flatWindowDepth
    }

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
