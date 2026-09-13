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
    public let roomPosition: SIMD3<Float>
    public let roomRotation: simd_quatf
    public let effectiveDistance: Float

    public init(
        center: SIMD3<Float>,
        right: SIMD3<Float>,
        up: SIMD3<Float>,
        normal: SIMD3<Float>,
        halfWidth: Float,
        halfHeight: Float,
        meshScale: Float,
        roomPosition: SIMD3<Float>,
        roomRotation: simd_quatf,
        effectiveDistance: Float
    ) {
        self.center = center
        self.right = right
        self.up = up
        self.normal = normal
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.meshScale = meshScale
        self.roomPosition = roomPosition
        self.roomRotation = roomRotation
        self.effectiveDistance = effectiveDistance
    }

    public var bottomEdgeCenter: SIMD3<Float> {
        center - halfHeight * up
    }
}

nonisolated public enum PlaybackDockedPoseSolver {
    public static func solve(
        transform: PlaybackSurfaceTransform,
        geometry: EnvironmentSceneGeometry,
        restPose: EnvironmentScreenRestPose,
        meshSize: SIMD2<Float>,
        roomOrigin: SIMD3<Float> = .zero
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
        let distance = Float(transform.distance)
        let yaw = simd_quatf(angle: restPose.yawRadians, axis: SIMD3<Float>(0, 1, 0))
        let pitch = simd_quatf(angle: elevation, axis: SIMD3<Float>(1, 0, 0))
        let worldRotation = yaw * pitch * yaw.inverse
        let pivot = SIMD3<Float>(0, restBottom, 0)
        let planarUp = SIMD3<Float>(0, cosE, sinE)
        let planarNormal = SIMD3<Float>(0, -sinE, cosE)
        let bottomEdge = pivot + distance * SIMD3<Float>(0, sinE, -cosE)
        let up = yaw.act(planarUp)
        let normal = yaw.act(planarNormal)
        let right = yaw.act(SIMD3<Float>(1, 0, 0))
        let center = yaw.act(bottomEdge + halfHeight * planarUp)
        let unrotatedRoomShift: SIMD3<Float>
        switch geometry.distanceStrategy {
        case .movesScreen:
            unrotatedRoomShift = .zero
        case .movesViewer:
            unrotatedRoomShift = yaw.act(
                SIMD3<Float>(0, 0, restDistance - distance)
            )
        }
        let roomPosition = pivot
            + worldRotation.act(roomOrigin + unrotatedRoomShift - pivot)
        let lift = SIMD3<Float>(0, -Float(transform.viewerHeight), 0)
        return PlaybackDockedPose(
            center: center + lift,
            right: right,
            up: up,
            normal: normal,
            halfWidth: halfWidth,
            halfHeight: halfHeight,
            meshScale: screenHeight / resolvedMesh.y,
            roomPosition: roomPosition + lift,
            roomRotation: worldRotation,
            effectiveDistance: distance
        )
    }
}
