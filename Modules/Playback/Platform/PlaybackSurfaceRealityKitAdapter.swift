import EnvironmentSceneContract
import Foundation
import RealityKit

@MainActor
enum PlaybackSurfaceAnchorResolver {
    static let canonicalName = "PlaybackSurfaceAnchor"
    static let legacyName = "screen"

    static func resolve(in world: Entity) throws -> Entity {
        let anchor: Entity
        if let canonical = world.findEntity(named: canonicalName) {
            anchor = canonical
        } else if let legacy = world.findEntity(named: legacyName) {
            legacy.name = canonicalName
            anchor = legacy
        } else {
            throw PlaybackSurfacePlatformError.missingAnchor
        }
        removePlaybackGeometry(from: anchor)
        return anchor
    }

    private static func removePlaybackGeometry(from entity: Entity) {
        entity.components.remove(ModelComponent.self)
        for child in entity.children {
            removePlaybackGeometry(from: child)
        }
    }
}

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
        anchorWorldPosition: SIMD3<Float>
    ) -> PlaybackDockedPose {
        if entity.parent !== anchor {
            anchor.addChild(entity)
        }
        let meshSize = entity.components[VideoPlayerComponent.self]?.playerScreenSize ?? .zero
        let pose = PlaybackDockedPoseSolver.solve(
            transform: transform,
            geometry: geometry,
            anchorWorldPosition: anchorWorldPosition,
            meshSize: meshSize
        )
        entity.look(at: pose.lookTarget, from: pose.center, relativeTo: nil)
        entity.scale = .init(repeating: pose.meshScale)
        return pose
    }

    static func screenState(
        of entity: Entity,
        pose: PlaybackDockedPose,
        videoTexture: TextureResource?
    ) -> EnvironmentScreenState {
        let orientation = entity.orientation(relativeTo: nil)
        return EnvironmentScreenState(
            center: entity.position(relativeTo: nil),
            right: simd_normalize(orientation.act([1, 0, 0])),
            up: simd_normalize(orientation.act([0, 1, 0])),
            halfWidth: pose.halfWidth,
            halfHeight: pose.halfHeight,
            videoTexture: videoTexture
        )
    }
}

private enum PlaybackSurfacePlatformError: LocalizedError {
    case missingAnchor

    var errorDescription: String? {
        "The selected environment does not contain PlaybackSurfaceAnchor."
    }
}
