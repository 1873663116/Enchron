import ARKit
import PlaybackPresentation
import QuartzCore
import RealityKit
import simd

@MainActor
enum ImmersivePlaybackControlsAttachmentPolicy {
    static func isVisible(
        presentation: PlaybackPresentation,
        controlsVisible: Bool,
        transitionIsActive: Bool
    ) -> Bool {
        presentation.usesImmersiveSpace
            && controlsVisible
            && transitionIsActive == false
    }
}

@MainActor
final class ImmersivePlaybackControlsAttachmentController: NSObject {
    static let attachmentID = "immersivePlaybackControlsAttachment"
    static let forwardOffsetMeters: Float = -0.7
    static let verticalOffsetMeters: Float = -0.22
    static let smoothingRetentionPer16Milliseconds: Float = 0.96

    private weak var appModel: AppModel?
    private var attachmentEntity: Entity?
    private var session: ARKitSession?
    private var provider: WorldTrackingProvider?
    private var displayLink: CADisplayLink?
    private var generation = UUID()
    private var lastFrameTimestamp: CFTimeInterval?
    private var hasAppliedPose = false

    func attach(_ entity: Entity, appModel: AppModel) {
        self.appModel = appModel
        if attachmentEntity !== entity {
            if let attachmentEntity {
                setEnabled(
                    false,
                    on: attachmentEntity,
                    writer: "ImmersivePlaybackControlsAttachmentController.attach.replaced"
                )
            }
            attachmentEntity = entity
            entity.name = "EnchronImmersivePlaybackControls"
            setEnabled(
                false,
                on: entity,
                writer: "ImmersivePlaybackControlsAttachmentController.attach.initial"
            )
            entity.components.set(OpacityComponent(opacity: 0))
            hasAppliedPose = false
            lastFrameTimestamp = nil
        }
        startTrackingIfNeeded()
    }

    func contains(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate === attachmentEntity { return true }
            current = candidate.parent
        }
        return false
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        session?.stop()
        session = nil
        provider = nil
        generation = UUID()
        lastFrameTimestamp = nil
        hasAppliedPose = false
        attachmentEntity?.components.set(OpacityComponent(opacity: 0))
        if let attachmentEntity {
            setEnabled(
                false,
                on: attachmentEntity,
                writer: "ImmersivePlaybackControlsAttachmentController.stop"
            )
        }
        attachmentEntity = nil
    }

    private func startTrackingIfNeeded() {
        guard session == nil,
              attachmentEntity != nil,
              WorldTrackingProvider.isSupported else {
            return
        }

        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        let generation = UUID()
        self.session = session
        self.provider = provider
        self.generation = generation

        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(updatePose(_:))
        )
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink

        Task { @MainActor [weak self] in
            do {
                try await session.run([provider])
            } catch {
                guard let self, self.generation == generation else { return }
                self.appModel?.recordSurfaceInputProbe(
                    "immersiveControlsAttachment trackingFailed=\(error.localizedDescription)"
                )
                self.stop()
            }
        }
    }

    @objc
    private func updatePose(_ displayLink: CADisplayLink) {
        guard let provider,
              let attachmentEntity,
              let anchor = provider.queryDeviceAnchor(
                atTimestamp: CACurrentMediaTime()
              ),
              anchor.isTracked else {
            lastFrameTimestamp = displayLink.timestamp
            if hasAppliedPose {
                hasAppliedPose = false
                self.attachmentEntity?.components.set(
                    OpacityComponent(opacity: 0)
                )
                if let attachmentEntity = self.attachmentEntity {
                    self.setEnabled(
                        false,
                        on: attachmentEntity,
                        writer: "ImmersivePlaybackControlsAttachmentController.updatePose.trackingLost"
                    )
                }
                appModel?.recordSurfaceInputProbe(
                    "immersiveControlsAttachment trackingLost"
                )
            }
            return
        }

        var offset = matrix_identity_float4x4
        offset.columns.3 = SIMD4<Float>(
            0,
            Self.verticalOffsetMeters,
            Self.forwardOffsetMeters,
            1
        )
        let target = Transform(matrix: anchor.originFromAnchorTransform * offset)
        let elapsed = lastFrameTimestamp.map {
            max(0, displayLink.timestamp - $0)
        } ?? 0
        lastFrameTimestamp = displayLink.timestamp

        if hasAppliedPose {
            let retention = pow(
                Self.smoothingRetentionPer16Milliseconds,
                Float(elapsed / 0.016)
            )
            let appliedFraction = 1 - retention
            var smoothed = attachmentEntity.transform
            smoothed.translation = simd_mix(
                smoothed.translation,
                target.translation,
                SIMD3<Float>(repeating: appliedFraction)
            )
            smoothed.rotation = simd_slerp(
                smoothed.rotation,
                target.rotation,
                appliedFraction
            )
            attachmentEntity.transform = smoothed
        } else {
            attachmentEntity.transform = target
            hasAppliedPose = true
            attachmentEntity.components.set(OpacityComponent(opacity: 1))
            setEnabled(
                true,
                on: attachmentEntity,
                writer: "ImmersivePlaybackControlsAttachmentController.updatePose.firstPose"
            )
            appModel?.recordSurfaceInputProbe(
                "immersiveControlsAttachment firstPoseApplied"
            )
        }
    }

    private func setEnabled(
        _ value: Bool,
        on entity: Entity,
        writer: String
    ) {
        let previous = entity.isEnabled
        entity.isEnabled = value
        guard previous != entity.isEnabled else { return }
        appModel?.recordSurfaceInputProbe(
            "entityEnablementWrite writer=\(writer)"
                + " entity=\(ObjectIdentifier(entity))"
                + " name=\(entity.name.isEmpty ? "unnamed" : entity.name)"
                + " value=\(value)"
                + " activeAfterWrite=\(entity.isActive)"
        )
    }
}
