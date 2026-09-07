import Foundation

public enum WindowPlaybackSurfaceGeometry {
    nonisolated public static let unitHeight: Float = 1
    nonisolated public static let defaultSurfaceSize =
        SIMD2<Float>(16.0 / 9.0, unitHeight)
    nonisolated public static let flatWindowDepth: CGFloat = 0
    nonisolated public static let projectedPortalDepth: CGFloat = 1
    nonisolated public static let backgroundSortOrder: Int32 = 0
    nonisolated public static let subtitleSortOrder: Int32 = backgroundSortOrder + 1
    nonisolated public static let coincidentChromeDepth: CGFloat = .ulpOfOne

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

    nonisolated public static func interactionRegion(
        screenSize: SIMD2<Float>,
        verticalFill: Float,
        occlusion: PlaybackWindowChromeOcclusion,
        thickness: Float,
        frontOffset: Float
    ) -> PlaybackWindowInteractionRegion? {
        let resolvedSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : defaultSurfaceSize
        let fill = verticalFill.isFinite && verticalFill > 0
            ? min(verticalFill, 1)
            : 1
        let occludedHeight = resolvedSize.y * min(occlusion.topFraction / fill, 1)
        let height = resolvedSize.y - occludedHeight
        guard height > 0 else { return nil }
        return PlaybackWindowInteractionRegion(
            size: [resolvedSize.x, height, thickness],
            center: [0, -occludedHeight / 2, frontOffset]
        )
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

public struct PlaybackWindowChromeOcclusion: Equatable, Sendable {
    nonisolated public static let none = PlaybackWindowChromeOcclusion()
    nonisolated public static let ornamentOverlapFraction: CGFloat = 0.5
    nonisolated public static let ornamentClearanceHeight: CGFloat = 12

    public let topFraction: Float
    public let bottomFraction: Float
    public let secondaryMenuIsPresented: Bool

    nonisolated public init(
        topFraction: Float = 0,
        bottomFraction: Float = 0,
        secondaryMenuIsPresented: Bool = false
    ) {
        self.topFraction = topFraction.isFinite ? min(max(topFraction, 0), 1) : 0
        self.bottomFraction = bottomFraction.isFinite ? min(max(bottomFraction, 0), 0.5) : 0
        self.secondaryMenuIsPresented = secondaryMenuIsPresented
    }

    nonisolated public static func bottomFraction(
        ornamentHeight: CGFloat,
        surfaceHeight: CGFloat
    ) -> Float {
        guard ornamentHeight > 0, surfaceHeight > 0 else { return 0 }
        let occluded = ornamentHeight * ornamentOverlapFraction + ornamentClearanceHeight
        return Float(min(max(occluded / surfaceHeight, 0), 0.5))
    }
}

public struct PlaybackWindowInteractionRegion: Equatable, Sendable {
    public let size: SIMD3<Float>
    public let center: SIMD3<Float>

    nonisolated public init(size: SIMD3<Float>, center: SIMD3<Float>) {
        self.size = size
        self.center = center
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
