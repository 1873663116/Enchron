import RealityKit
import SwiftUI
import simd

@MainActor
final class PlaybackSurfaceSeekAttachment {
    static let attachmentID = "playbackSurfaceSeekFeedback"

    private weak var attachment: Entity?
    private weak var headPoseSource: HeadPoseSource?
    private var isVisible = false

    func install(
        _ entity: Entity,
        visible: Bool,
        presentation: PlaybackPresentation,
        videoEntity: Entity,
        content: RealityViewContent,
        headPoseSource: HeadPoseSource
    ) {
        if attachment !== entity {
            attachment?.isEnabled = false
            attachment = entity
            isVisible = false
        }
        if self.headPoseSource !== headPoseSource {
            self.headPoseSource?.release(self)
            self.headPoseSource = headPoseSource
            headPoseSource.retain(self)
        }
        entity.name = "EnchronPlaybackSurfaceSeekFeedback"
        entity.components.remove(InputTargetComponent.self)
        entity.components.remove(CollisionComponent.self)
        let shouldShow = visible && presentation.usesImmersiveSpace
        if shouldShow, isVisible == false {
            switch presentation {
            case .panorama:
                entity.removeFromParent()
                content.add(entity)
                let pose: simd_float4x4
                switch headPoseSource.pose() {
                case let .pose(value):
                    pose = value
                case .unavailable:
                    pose = matrix_identity_float4x4
                }
                entity.transform = ImmersivePlaybackControlsPlacementGeometry.transform(
                    originFromAnchorTransform: pose,
                    forwardOffsetMeters: -2,
                    verticalOffsetMeters: 0,
                    tiltRadians: 0,
                    panelScale: 2.43
                )
            case .docked:
                videoEntity.addChild(entity)
                entity.transform = Transform(
                    scale: .one,
                    rotation: .init(),
                    translation: [0, 0, 0.04]
                )
            case .window, .portal:
                break
            }
        }
        isVisible = shouldShow
        entity.isEnabled = shouldShow
    }

    func stop() {
        attachment?.isEnabled = false
        attachment?.removeFromParent()
        attachment = nil
        isVisible = false
        headPoseSource?.release(self)
        headPoseSource = nil
    }
}
