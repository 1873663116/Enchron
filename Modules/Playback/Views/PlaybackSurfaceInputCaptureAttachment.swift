import CoreGraphics
import RealityKit
import simd

@MainActor
final class PlaybackSurfaceInputCaptureAttachment {
    static let attachmentID = "playbackSurfaceInputCapture"
    static let nominalSizePoints: CGFloat = 1024

    static func attachmentFrame(
        forPlaneSize planeSize: SIMD2<Float>
    ) -> (width: CGFloat, height: CGFloat) {
        let aspect = CGFloat(planeSize.y / planeSize.x)
        return (nominalSizePoints, nominalSizePoints * aspect)
    }

    private weak var attachment: Entity?

    func install(
        _ entity: Entity,
        on videoEntity: Entity,
        screenSize: SIMD2<Float>
    ) {
        if attachment !== entity {
            attachment = entity
            entity.name = "EnchronPlaybackSurfaceInputCapture"
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
        }
        if entity.parent !== videoEntity {
            videoEntity.addChild(entity)
        }
        entity.isEnabled = true
        entity.position = [0, 0, 0.015]
        entity.orientation = .init()
        let bounds = entity.visualBounds(relativeTo: videoEntity)
        guard bounds.extents.x > 0 else { return }
        let currentScaleX = max(entity.scale.x, 0.0001)
        let unscaledWidth = bounds.extents.x / currentScaleX
        guard unscaledWidth > 0 else { return }
        let scale = screenSize.x / unscaledWidth
        entity.scale = SIMD3<Float>(repeating: scale)
    }

    func stop() {
        attachment?.isEnabled = false
        attachment?.removeFromParent()
        attachment = nil
    }
}
