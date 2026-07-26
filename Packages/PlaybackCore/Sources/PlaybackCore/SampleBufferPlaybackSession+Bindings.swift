@preconcurrency import AVFoundation
import Foundation
import OSLog

extension SampleBufferPlaybackSession {
    func interruptionRecoveryRate() -> Float {
        mediaSessionRecord?.lifecycle == .playing ? preferredPlaybackRate : 0
    }

    public func debugEvents() -> AsyncStream<PlaybackDebugEvent> {
        debugStore.events()
    }

    public func debugSnapshot() -> PlaybackDebugSnapshotV1 {
        debugStore.snapshot()
    }

    public func debugSnapshotJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(debugStore.snapshot()), as: UTF8.self)
    }

    public func correlateEvidenceID(_ evidenceID: String) {
        debugStore.correlateEvidenceID(evidenceID)
    }

    public func recordDebugCommand(_ command: String) {
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "debug.command.received",
            outcome: .succeeded,
            details: ["command": command]
        )
    }

    func admitTimelineControl(
        _ kind: PlaybackOperationKind,
        targetRate: Float? = nil
    ) throws {
        guard !isClosed else {
            rejectControl(kind, reason: "mediaSessionClosed", targetRate: targetRate)
            throw PlaybackControlError.mediaSessionClosed
        }
        guard hasStartedTimeline else {
            rejectControl(kind, reason: "timelineNotReady", targetRate: targetRate)
            throw PlaybackControlError.timelineNotReady
        }
    }

    func rejectControl(
        _ kind: PlaybackOperationKind,
        reason: String,
        targetTimeSeconds: Double? = nil,
        targetRate: Float? = nil
    ) {
        let rejection = ControlRejectionRecord(
            mediaSessionID: traceID,
            kind: kind,
            reason: reason,
            targetTimeSeconds: targetTimeSeconds,
            targetRate: targetRate
        )
        debugStore.recordControlRejection(rejection)
        debugStore.emit(
            mediaSessionID: traceID,
            kind: PlaybackArtifactEventName.controlRejected(kind).rawValue,
            outcome: .failed,
            details: ["reason": reason]
        )
    }

    func recordSupersededSeekRequest(targetSeconds: Double) {
        let operation = PlaybackOperationRecord(
            mediaSessionID: traceID,
            kind: .seek,
            targetTimeSeconds: targetSeconds
        ).finishing(as: .terminatedByCleanup)
        debugStore.recordOperation(operation)
        debugStore.emit(
            mediaSessionID: traceID,
            kind: "operation.seek.superseded",
            outcome: .terminatedByCleanup,
            details: [
                "operationID": operation.operationID,
                "targetSeconds": String(targetSeconds),
            ]
        )
    }

    public func recordRealityKitBinding(entityIdentity: String, active: Bool) {
        let current = debugStore.snapshot().realityKitBinding
        if isClosed || (active && current?.entityIdentity != nil && current?.entityIdentity != entityIdentity) ||
            (!active && current?.entityIdentity != nil && current?.entityIdentity != entityIdentity) {
            debugStore.recordStaleRejection()
            debugStore.emit(
                mediaSessionID: traceID,
                node: .realityKitRendererBinding,
                kind: "realityKit.bindingRejected",
                outcome: .failed,
                details: ["entity": entityIdentity]
            )
            return
        }
        if active, current?.entityIdentity == entityIdentity, current?.active == true { return }
        if !active, current == nil { return }
        let record = active ? RealityKitBindingRecord(
            mediaSessionID: traceID,
            bindingID: "\(traceID).realityKitBinding",
            graphID: "\(traceID).rendererGraph",
            rendererIdentity: PlaybackTrace.identity(renderer),
            componentAttached: true,
            componentRendererIdentity: PlaybackTrace.identity(renderer),
            entityIdentity: entityIdentity,
            active: true
        ) : nil
        debugStore.recordRealityKitBinding(record)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .realityKitRendererBinding,
            kind: active ? "realityKit.bound" : "realityKit.unbound",
            outcome: active ? .succeeded : .terminatedByCleanup,
            details: ["entity": entityIdentity]
        )
    }

    public func recordPresentationBinding(
        realityViewIdentity: String,
        platform: String,
        attached: Bool,
        sceneContainer: String = "WindowGroup",
        sceneLifecycle: String = "activeRealityView"
    ) {
        let current = debugStore.snapshot().presentationBinding
        if isClosed ||
            (attached && current?.realityViewIdentity != nil &&
                current?.realityViewIdentity != realityViewIdentity) ||
            (!attached && current?.realityViewIdentity != nil &&
                current?.realityViewIdentity != realityViewIdentity) {
            debugStore.recordStaleRejection()
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererConsumerBinding,
                kind: "presentation.bindingRejected",
                outcome: .failed,
                details: ["realityView": realityViewIdentity]
            )
            return
        }
        if attached,
           current?.realityViewIdentity == realityViewIdentity,
           current?.entityAttached == true { return }
        if !attached, current == nil { return }
        if attached, mediaSessionRecord?.lifecycle == .opening {
            updateLifecycle(.ready)
        }
        let record = attached ? PresentationBindingRecord(
            mediaSessionID: traceID,
            presentationBindingID: "\(traceID).presentationBinding",
            rendererBindingID: "\(traceID).realityKitBinding",
            realityViewIdentity: realityViewIdentity,
            entityAttached: true,
            platform: platform,
            provenance: "appAdapter",
            appAdapterKind: "externalAppAdapter",
            sceneContainer: .init(known: sceneContainer),
            sceneLifecycle: .init(known: sceneLifecycle)
        ) : nil
        debugStore.recordPresentationBinding(record)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererConsumerBinding,
            kind: attached ? "presentation.attached" : "presentation.detached",
            outcome: attached ? .succeeded : .terminatedByCleanup,
            details: [
                "realityView": realityViewIdentity,
                "platform": platform,
            ]
        )
        if attached, activeOperation?.kind == .open {
            finishActiveOperation(.completed)
        }
    }

    public func recordPresentationState(_ record: PresentationStateRecord) {
        guard !isClosed,
              record.mediaSessionID == traceID else {
            debugStore.recordStaleRejection()
            debugStore.emit(
                mediaSessionID: traceID,
                node: .rendererConsumerBinding,
                kind: "presentation.stateRejected",
                outcome: .failed
            )
            return
        }
        debugStore.recordPresentationState(record)
        debugStore.emit(
            mediaSessionID: traceID,
            node: .rendererConsumerBinding,
            kind: "presentation.stateChanged",
            outcome: record.transitionError.availability == .known ? .failed : .succeeded,
            details: [
                "requestedMode": record.requestedMode,
                "phase": record.phase,
                "sceneContainer": eventValue(record.sceneContainer),
                "desiredImmersiveViewingMode": eventValue(record.desiredImmersiveViewingMode),
                "actualImmersiveViewingMode": eventValue(record.actualImmersiveViewingMode),
                "desiredViewingMode": eventValue(record.desiredViewingMode),
                "actualViewingMode": eventValue(record.actualViewingMode),
                "desiredSpatialVideoMode": eventValue(record.desiredSpatialVideoMode),
                "actualSpatialVideoMode": eventValue(record.actualSpatialVideoMode),
            ]
        )
    }

    func eventValue(_ fact: ObservedStringFact) -> String {
        fact.value ?? fact.availability.rawValue
    }

}
