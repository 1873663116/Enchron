import RealityKit
import simd

@MainActor
public enum ImmersivePlaybackControlsAttachmentPolicy {
    static func isVisible(
        presentation: PlaybackPresentation,
        controlsVisible: Bool,
        transitionIsActive: Bool
    ) -> Bool {
        guard controlsVisible else { return false }
        return switch presentation {
        case .docked:
            true
        case .panorama:
            transitionIsActive == false
        case .window, .portal:
            false
        }
    }
}

struct ImmersivePlaybackControlsPlacementState: Equatable {
    enum Action: Equatable {
        case none
        case place(revision: UInt64)
        case hide(lastPlacementRevision: UInt64)
    }

    enum Placement: Equatable {
        case headAnchor(revision: UInt64)
        case fallback(revision: UInt64)
    }

    private(set) var isVisible = false
    private(set) var placementRevision: UInt64 = 0
    private(set) var pendingPlacementRevision: UInt64?

    mutating func setVisible(_ visible: Bool) -> Action {
        guard visible != isVisible else { return .none }
        isVisible = visible
        if visible {
            placementRevision &+= 1
            pendingPlacementRevision = placementRevision
            return .place(revision: placementRevision)
        }
        pendingPlacementRevision = nil
        return .hide(lastPlacementRevision: placementRevision)
    }

    mutating func resolvePlacement(headAnchorIsAvailable: Bool) -> Placement? {
        guard isVisible, let revision = pendingPlacementRevision else {
            return nil
        }
        pendingPlacementRevision = nil
        if headAnchorIsAvailable {
            return .headAnchor(revision: revision)
        }
        return .fallback(revision: revision)
    }
}

@MainActor
final class ImmersivePlaybackControlsAttachmentController {
    static let attachmentID = "immersivePlaybackControlsAttachment"
    static let forwardOffsetMeters: Float = -0.7
    static let verticalOffsetMeters: Float = -0.22

    var lockedControlsTransform: Transform? {
        placementState.isVisible ? lockedTransform : nil
    }

    private weak var appModel: PlaybackSessionModel?
    private var attachmentEntity: Entity?
    private var headPoseSource: HeadPoseSource?
    private var placementState = ImmersivePlaybackControlsPlacementState()
    private var lockedTransform: Transform?

    func attach(
        _ entity: Entity,
        appModel: PlaybackSessionModel,
        headPoseSource: HeadPoseSource
    ) {
        self.appModel = appModel
        if self.headPoseSource !== headPoseSource {
            self.headPoseSource?.release(self)
            self.headPoseSource = headPoseSource
        }
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
            if placementState.isVisible, let lockedTransform {
                applyLockedTransform(lockedTransform, to: entity)
            }
        }
        retainHeadPoseIfNeeded()
        placeForPendingVisibilityRiseIfPossible()
    }

    func setVisible(_ visible: Bool) {
        switch placementState.setVisible(visible) {
        case .none:
            break
        case let .place(revision):
            lockedTransform = nil
            hideAttachment(
                writer: "ImmersivePlaybackControlsAttachmentController.setVisible.place"
            )
            appModel?.recordSurfaceInputProbe(
                "immersiveControlsAttachment placementRequested revision=\(revision)",
                retention: .evidence
            )
            retainHeadPoseIfNeeded()
            placeForPendingVisibilityRiseIfPossible()
        case let .hide(lastPlacementRevision):
            lockedTransform = nil
            hideAttachment(
                writer: "ImmersivePlaybackControlsAttachmentController.setVisible.hide"
            )
            appModel?.recordSurfaceInputProbe(
                "immersiveControlsAttachment placementStopped"
                    + " revision=\(lastPlacementRevision) reason=hidden",
                retention: .evidence
            )
        }
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
        headPoseSource?.release(self)
        headPoseSource = nil
        lockedTransform = nil
        placementState = ImmersivePlaybackControlsPlacementState()
        hideAttachment(writer: "ImmersivePlaybackControlsAttachmentController.stop")
        attachmentEntity = nil
    }

    private func retainHeadPoseIfNeeded() {
        guard attachmentEntity != nil, let headPoseSource else { return }
        headPoseSource.retain(
            self,
            onReady: { [weak self] in
                self?.placeForPendingVisibilityRiseIfPossible()
            },
            onFailure: { [weak self] reason in
                self?.appModel?.recordSurfaceInputProbe(
                    "immersiveControlsAttachment trackingFailed=\(reason)"
                )
            }
        )
    }

    private func placeForPendingVisibilityRiseIfPossible() {
        guard placementState.isVisible,
              placementState.pendingPlacementRevision != nil,
              let attachmentEntity else {
            return
        }

        let revision = placementState.pendingPlacementRevision!
        let headPose: (originTransform: simd_float4x4?, fallbackReason: String)
        if let headPoseSource, headPoseSource.isRunning {
            let reading = headPoseSource.pose()
            appModel?.recordSurfaceInputProbe(
                "immersiveControlsAttachment headPoseQueried revision=\(revision)",
                retention: .evidence
            )
            switch reading {
            case let .pose(originFromAnchorTransform):
                headPose = (originFromAnchorTransform, "")
            case let .unavailable(reason):
                headPose = (nil, reason)
            }
        } else {
            headPose = (nil, HeadPoseSource.Reading.trackingUnavailableReason)
        }
        guard let placement = placementState.resolvePlacement(
            headAnchorIsAvailable: headPose.originTransform != nil
        ) else {
            return
        }

        let originFromAnchorTransform: simd_float4x4
        switch placement {
        case .headAnchor:
            originFromAnchorTransform = headPose.originTransform!
        case .fallback:
            originFromAnchorTransform = matrix_identity_float4x4
            appModel?.recordSurfaceInputProbe(
                "immersiveControlsAttachment placementFallback"
                    + " reason=\(headPose.fallbackReason) revision=\(revision)",
                retention: .evidence
            )
        }

        var offset = matrix_identity_float4x4
        offset.columns.3 = SIMD4<Float>(
            0,
            Self.verticalOffsetMeters,
            Self.forwardOffsetMeters,
            1
        )
        let transform = Transform(
            matrix: originFromAnchorTransform * offset
        )
        lockedTransform = transform
        applyLockedTransform(transform, to: attachmentEntity)
        appModel?.recordSurfaceInputProbe(
            "immersiveControlsAttachment placementApplied revision=\(revision)",
            retention: .evidence
        )
        appModel?.recordSurfaceInputProbe(
            "immersiveControlsAttachment placementStopped"
                + " revision=\(revision) reason=worldLocked",
            retention: .evidence
        )
    }

    private func applyLockedTransform(_ transform: Transform, to entity: Entity) {
        entity.transform = transform
        entity.components.set(OpacityComponent(opacity: 1))
        setEnabled(
            true,
            on: entity,
            writer: "ImmersivePlaybackControlsAttachmentController.applyLockedTransform"
        )
    }

    private func hideAttachment(writer: String) {
        attachmentEntity?.components.set(OpacityComponent(opacity: 0))
        if let attachmentEntity {
            setEnabled(false, on: attachmentEntity, writer: writer)
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
