import EnvironmentSceneContract
import simd

nonisolated public struct PlaybackDockedPose: Equatable, Sendable {
    public let center: SIMD3<Float>
    public let right: SIMD3<Float>
    public let up: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let halfWidth: Float
    public let halfHeight: Float
    public let meshScale: Float
    public let roomOffset: SIMD3<Float>
    public let effectiveDistance: Float
    public let ceilingClamped: Bool

    public init(
        center: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>,
        normal: SIMD3<Float>,
        halfWidth: Float,
        halfHeight: Float,
        meshScale: Float,
        roomOffset: SIMD3<Float>,
        effectiveDistance: Float,
        ceilingClamped: Bool
    ) {
        self.center = center
        self.right = right
        self.up = up
        self.normal = normal
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.meshScale = meshScale
        self.roomOffset = roomOffset
        self.effectiveDistance = effectiveDistance
        self.ceilingClamped = ceilingClamped
    }

    public var bottomEdgeCenter: SIMD3<Float> {
        center - halfHeight * up
    }
}

nonisolated public enum PlaybackDockedPoseSolver {
    public static let minimumEffectiveDistance: Float = 0.5

    public static func solve(
        transform: PlaybackSurfaceTransform,
        geometry: EnvironmentSceneGeometry,
        restPose: EnvironmentScreenRestPose,
        meshSize: SIMD2<Float>
    ) -> PlaybackDockedPose {
        let restBottom = restPose.bottomHeight
        let restDistance = restPose.distance
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
        var distance: Float
        switch geometry.distanceStrategy {
        case .movesScreen:
            distance = Float(transform.distance)
        case .movesViewer:
            distance = restDistance
        }
        var ceilingClamped = false
        if let ceiling = geometry.ceilingHeightMeters {
            let limit = ceiling - geometry.ceilingClearanceMeters
            let topOffset = 2 * halfHeight * cosE
            if sinE > 1e-4, distance * sinE + restBottom + topOffset > limit {
                distance = max(
                    minimumEffectiveDistance,
                    (limit - restBottom - topOffset) / sinE
                )
                ceilingClamped = true
            }
        }
        let yaw = simd_quatf(angle: restPose.yawRadians, axis: SIMD3<Float>(0, 1, 0))
        let planarUp = SIMD3<Float>(0, cosE, sinE)
        let planarNormal = SIMD3<Float>(0, -sinE, cosE)
        let bottomEdge = SIMD3<Float>(0, restBottom, 0)
            + distance * SIMD3<Float>(0, sinE, -cosE)
        let up = yaw.act(planarUp)
        let normal = yaw.act(planarNormal)
        let right = yaw.act(SIMD3<Float>(1, 0, 0))
        let center = yaw.act(bottomEdge + halfHeight * planarUp)
        let roomOffset: SIMD3<Float>
        switch geometry.distanceStrategy {
        case .movesScreen:
            roomOffset = .zero
        case .movesViewer:
            roomOffset = yaw.act(
                SIMD3<Float>(0, 0, restDistance - Float(transform.distance))
            )
        }
        return PlaybackDockedPose(
            center: center,
            right: right,
            up: up,
            normal: normal,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            meshScale: screenHeight / resolvedMesh.y,
            roomOffset: roomOffset,
            effectiveDistance: distance,
            ceilingClamped: ceilingClamped
        )
    }
}
