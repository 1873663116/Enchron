import EnvironmentSceneContract
import simd

nonisolated public struct PlaybackDockedPose: Equatable, Sendable {
    public let viewerReference: SIMD3<Float>
    public let center: SIMD3<Float>
    public let effectiveDistance: Float
    public let halfWidth: Float
    public let halfHeight: Float
    public let meshScale: Float
    public let roomOffsetZ: Float

    public var lookTarget: SIMD3<Float> {
        center + (center - viewerReference)
    }

    public var ceilingClamped: Bool
}

nonisolated public enum PlaybackDockedPoseSolver {
    public static let minimumEffectiveDistance: Float = 0.5

    public static func solve(
        transform: PlaybackSurfaceTransform,
        geometry: EnvironmentSceneGeometry,
        anchorWorldPosition: SIMD3<Float>,
        meshSize: SIMD2<Float>
    ) -> PlaybackDockedPose {
        let restHeight = geometry.screenRestHeightMeters ?? anchorWorldPosition.y
        let viewerReference = SIMD3<Float>(0, restHeight, 0)
        let elevation = Float(transform.elevationDegrees) * .pi / 180
        let sinE = sin(elevation)
        let cosE = cos(elevation)
        let screenHeight = Float(transform.scale)
        let resolvedMesh = meshSize.x > 0 && meshSize.y > 0
            ? meshSize
            : WindowPlaybackSurfaceGeometry.defaultSurfaceSize
        let aspect = resolvedMesh.x / resolvedMesh.y
        let halfHeight = screenHeight / 2
        let halfWidth = halfHeight * aspect
        var distance = Float(transform.distance)
        var clamped = false
        if let ceiling = geometry.ceilingHeightMeters {
            let limit = ceiling - geometry.ceilingClearanceMeters - restHeight
            let topOffset = halfHeight * cosE
            if sinE > 1e-4, distance * sinE + topOffset > limit {
                distance = max(minimumEffectiveDistance, (limit - topOffset) / sinE)
                clamped = true
            }
        }
        let center = viewerReference + SIMD3<Float>(0, distance * sinE, -distance * cosE)
        let roomOffsetZ: Float
        switch geometry.distanceStrategy {
        case .movesScreen:
            roomOffsetZ = 0
        case .movesViewer:
            roomOffsetZ = -anchorWorldPosition.z - Float(transform.distance)
        }
        return PlaybackDockedPose(
            viewerReference: viewerReference,
            center: center,
            effectiveDistance: distance,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            meshScale: screenHeight / resolvedMesh.y,
            roomOffsetZ: roomOffsetZ,
            ceilingClamped: clamped
        )
    }
}
