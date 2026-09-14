import EnvironmentSceneContract
import Foundation
import RealityKit

@MainActor
enum PlaybackSurfacePlacement {
    static func window(
        _ entity: Entity,
        sceneCenter: SIMD3<Float> = .zero
    ) {
        entity.position = sceneCenter
        entity.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        entity.scale = .one
    }

    @discardableResult
    static func dock(
        _ entity: Entity,
        to anchor: Entity,
        transform: PlaybackSurfaceTransform,
        geometry: EnvironmentSceneGeometry,
        restPose: EnvironmentScreenRestPose,
        roomOrigin: SIMD3<Float> = .zero
    ) -> PlaybackDockedPose {
        if entity.parent !== anchor {
            anchor.addChild(entity)
        }
        let meshSize = entity.components[VideoPlayerComponent.self]?.playerScreenSize ?? .zero
        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            restPose: restPose,
            meshSize: meshSize,
            roomOrigin: roomOrigin
        )
        let basis = simd_float3x3(pose.right, pose.up, pose.normal)
        entity.setOrientation(simd_quatf(basis), relativeTo: nil)
        entity.setPosition(pose.center, relativeTo: nil)
        entity.scale = .init(repeating: pose.meshScale)
        return pose
    }

    static func screenState(
        pose: PlaybackDockedPose,
        videoTexture: TextureResource?
    ) -> EnvironmentScreenState {
        EnvironmentScreenState(
            center: pose.center,
            right: pose.right,
            up: pose.up,
            halfWidth: pose.halfWidth,
            halfHeight: pose.halfHeight,
            videoTexture: videoTexture
        )
    }
}
