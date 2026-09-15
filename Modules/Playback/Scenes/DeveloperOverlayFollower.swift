import RealityKit
import SwiftUI
import simd

@MainActor
final class DeveloperOverlayFollower {
    static let attachmentID = "developerStatsOverlay"

    static let distanceMeters: Float = 0.7
    static let verticalOffsetMeters: Float = 0.10
    static let declinationRadians: Float = 30 * .pi / 180

    let root: Entity = {
        let entity = Entity()
        entity.name = "EnchronDeveloperOverlay.follower"
        return entity
    }()

    private var follow = LazyGazeFollow()
    private var headPoseSource: HeadPoseSource?
    private var updateSubscription: EventSubscription?
    private var attachment: Entity?

    static var localPlacement: SIMD3<Float> {
        [
            0,
            -distanceMeters * tan(declinationRadians) + verticalOffsetMeters,
            -distanceMeters
        ]
    }

    func setActive(
        _ active: Bool,
        attachment entity: Entity?,
        in content: RealityViewContent,
        headPoseSource: HeadPoseSource
    ) {
        guard active, let entity else {
            stop()
            if content.entities.contains(where: { $0 === root }) {
                content.remove(root)
            }
            return
        }

        if content.entities.contains(where: { $0 === root }) == false {
            content.add(root)
        }
        if attachment !== entity {
            attachment?.removeFromParent()
            attachment = entity
            entity.name = "EnchronDeveloperOverlay.attachment"
            root.addChild(entity)
        }
        entity.position = Self.localPlacement

        if self.headPoseSource !== headPoseSource {
            self.headPoseSource?.release(self)
            self.headPoseSource = headPoseSource
        }
        headPoseSource.retain(self)

        if updateSubscription == nil {
            updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                self?.step(deltaTime: Float(event.deltaTime))
            }
        }
    }

    func stop() {
        updateSubscription?.cancel()
        updateSubscription = nil
        headPoseSource?.release(self)
        headPoseSource = nil
        follow = LazyGazeFollow()
        attachment?.removeFromParent()
        attachment = nil
        root.removeFromParent()
    }

    private func step(deltaTime: Float) {
        guard let headPoseSource,
              case let .pose(transform) = headPoseSource.pose() else {
            return
        }
        let forward = -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let headPosition = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let gaze = LazyGazeFollow.gaze(of: forward)
        follow.advance(towardYaw: gaze.yaw, pitch: gaze.pitch, deltaTime: deltaTime)
        root.transform = Transform(
            scale: .one,
            rotation: follow.orientation,
            translation: headPosition
        )
    }
}
