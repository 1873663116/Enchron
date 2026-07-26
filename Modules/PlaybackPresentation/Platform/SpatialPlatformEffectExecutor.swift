import Foundation
import Observation
import PlaybackPresentation
import SwiftUI

#if os(visionOS)
@MainActor
@Observable
final class SpatialPlatformEffectCoordinator {
    private struct SceneActions {
        let openImmersiveSpace: OpenImmersiveSpaceAction
        let dismissImmersiveSpace: DismissImmersiveSpaceAction
        let openWindow: OpenWindowAction
        let dismissWindow: DismissWindowAction
    }

    private struct Execution {
        let request: SpatialPlatformEffectRequest
        let lease: SpatialPlatformExecutionLease
        let actions: SceneActions
    }

    private struct ActiveTask {
        let lease: SpatialPlatformExecutionLease
        let task: Task<Void, Never>
    }

    private struct ExecutionProgress {
        var didIssueVisibleSpatialSideEffect = false
    }

    private enum ImmersiveOpenDisposition: Sendable {
        case preexisting
        case openedByRequest
        case unavailable
    }

    private enum ExecutionPhase {
        case currentRequest
        case settledRequest
    }

    private enum GuardedTransportResult {
        case succeeded
        case invalidated
        case failed(
            reason: SpatialPlaybackTransportFailureReason,
            message: String
        )
    }

    private let appModel: AppModel
    private let playbackRuntime: PlaybackRuntime

    @ObservationIgnored
    private var leaseRegistry =
        SpatialPlatformExecutionLeaseRegistry<SceneActions>()
    @ObservationIgnored
    private var activeTask: ActiveTask?
    @ObservationIgnored
    private let immersiveActionLane = SpatialPlatformSerializedActionLane()
    @ObservationIgnored
    private var executionProgress: [UUID: ExecutionProgress] = [:]
    @ObservationIgnored
    private var immersiveRequestProvenance =
        SpatialPlatformImmersiveRequestProvenanceRegistry()
    @ObservationIgnored
    private var platformImmersiveSpaceResidency:
        SpatialPlatformImmersiveSpaceResidency?

    init(appModel: AppModel, playbackRuntime: PlaybackRuntime) {
        self.appModel = appModel
        self.playbackRuntime = playbackRuntime
        appModel.setSpatialPlatformEffectReplacementHandler { [weak self] in
            self?.requestDrain()
        }
    }

    func register(
        id: UUID,
        openImmersiveSpace: OpenImmersiveSpaceAction,
        dismissImmersiveSpace: DismissImmersiveSpaceAction,
        openWindow: OpenWindowAction,
        dismissWindow: DismissWindowAction
    ) {
        let invalidatedLease = leaseRegistry.register(
            SceneActions(
                openImmersiveSpace: openImmersiveSpace,
                dismissImmersiveSpace: dismissImmersiveSpace,
                openWindow: openWindow,
                dismissWindow: dismissWindow
            ),
            id: id
        )
        if let invalidatedLease {
            invalidateTask(invalidatedLease)
        }
        requestDrain()
    }

    func unregister(id: UUID) {
        if let invalidatedLease = leaseRegistry.unregister(id: id) {
            invalidateTask(invalidatedLease)
        }
        requestDrain()
    }

    func recordImmersiveSpaceResidency(
        _ residency: SpatialPlatformImmersiveSpaceResidency
    ) {
        platformImmersiveSpaceResidency = residency
    }

    func playbackSessionLifecycleChanged(
        _ event: PlaybackRuntime.SessionLifecycleEvent
    ) {
        guard let previousID = Self.invalidatedMediaSessionID(for: event),
              let lease = leaseRegistry.activeLease,
              lease.mediaSessionID == previousID else {
            return
        }
        invalidateExecutionForMediaSessionChange(lease)
    }

    static func invalidatedMediaSessionID(
        for event: PlaybackRuntime.SessionLifecycleEvent
    ) -> String? {
        switch event {
        case .replaced(let previousID, _), .ended(let previousID):
            previousID
        case .activated:
            nil
        }
    }

    func requestDrain() {
        let pendingRequest = appModel.pendingSpatialPlatformEffect
        immersiveRequestProvenance.retainOnly(
            requestID: pendingRequest?.id
        )
        if let activeLease = leaseRegistry.activeLease,
           activeLease.requestID != pendingRequest?.id,
           let invalidatedLease = leaseRegistry.invalidateActiveExecution() {
            immersiveRequestProvenance.clear(
                requestID: invalidatedLease.requestID
            )
            invalidateTask(invalidatedLease)
        }

        guard activeTask == nil,
              let request = appModel.pendingSpatialPlatformEffect,
              let claim = leaseRegistry.claim(
                requestID: request.id,
                mediaSessionID: request.playbackTransportPlan?.mediaSessionID
              ) else {
            return
        }
        guard appModel.claimSpatialPlatformEffect(
            request.id,
            executionID: claim.lease.executionID
        ) else {
            leaseRegistry.finish(claim.lease)
            return
        }

        let execution = Execution(
            request: request,
            lease: claim.lease,
            actions: claim.capability
        )
        executionProgress[execution.lease.executionID] = ExecutionProgress()
        let task = Task { [weak self] in
            guard let self else { return }
            await execute(execution)
            finishExecution(execution.lease)
        }
        activeTask = ActiveTask(lease: execution.lease, task: task)
    }

    private func invalidateTask(_ lease: SpatialPlatformExecutionLease) {
        if activeTask?.lease == lease {
            activeTask?.task.cancel()
            activeTask = nil
        }
        executionProgress[lease.executionID] = nil
        appModel.receiveSpatialPlatformResult(
            .effectExecutionAbandoned(
                requestID: lease.requestID,
                executionID: lease.executionID
            )
        )
    }

    private func finishExecution(_ lease: SpatialPlatformExecutionLease) {
        if appModel.isSpatialPlatformEffectCurrent(
            lease.requestID,
            executionID: lease.executionID
        ) {
            appModel.receiveSpatialPlatformResult(
                .effectExecutionAbandoned(
                    requestID: lease.requestID,
                    executionID: lease.executionID
                )
            )
        }
        leaseRegistry.finish(lease)
        if activeTask?.lease == lease {
            activeTask = nil
        }
        executionProgress[lease.executionID] = nil
        requestDrain()
    }

    private func invalidateExecutionForMediaSessionChange(
        _ lease: SpatialPlatformExecutionLease
    ) {
        guard leaseRegistry.activeLease == lease,
              appModel.isSpatialPlatformEffectCurrent(
                lease.requestID,
                executionID: lease.executionID
              ) else {
            return
        }
        let requiresPlatformNormalization =
            executionProgress[lease.executionID]?
                .didIssueVisibleSpatialSideEffect == true
            || platformImmersiveSpaceResidency == .open
            || appModel.immersiveSpaceResidency == .open
            || appModel.playbackPresentation != .window
        _ = leaseRegistry.invalidateActiveExecution()
        if activeTask?.lease == lease {
            activeTask?.task.cancel()
            activeTask = nil
        }
        executionProgress[lease.executionID] = nil
        appModel.receiveSpatialPlatformResult(
            .mediaSessionInvalidated(
                requestID: lease.requestID,
                executionID: lease.executionID,
                requiresPlatformNormalization: requiresPlatformNormalization
            )
        )
        immersiveRequestProvenance.clear(requestID: lease.requestID)
        requestDrain()
    }

    private func execute(_ execution: Execution) async {
        guard executionIsLive(execution) else { return }

        if let beforeEffect = execution.request.playbackTransportPlan?.beforeEffect {
            switch executePlaybackTransport(beforeEffect, execution: execution) {
            case .succeeded:
                break
            case .invalidated:
                return
            case .failed(let reason, let message):
                guard setRuntimeError(message, execution: execution) else { return }
                if reason == .mediaSessionChanged {
                    invalidateExecutionForMediaSessionChange(execution.lease)
                } else {
                    _ = complete(
                        execution,
                        outcome: .failed(.playbackPauseFailed),
                        performsAfterTransport: false
                    )
                }
                return
            }
        }

        switch execution.request.effect {
        case .presentSpatialPlayback(let presentation):
            await presentSpatialPlayback(presentation, execution: execution)
        case .recoverSpatialPlayback(let presentation):
            await recoverSpatialPlayback(presentation, execution: execution)
        case .presentWindowPlayback(
            let keepsEnvironmentOpen,
            let immersiveSpaceAlreadyClosed
        ):
            await presentWindowPlayback(
                execution: execution,
                keepsEnvironmentOpen: keepsEnvironmentOpen,
                immersiveSpaceAlreadyClosed: immersiveSpaceAlreadyClosed
            )
        case .presentEnvironmentPreview:
            await presentEnvironmentPreview(execution)
        case .dismissEnvironmentPreview:
            await dismissEnvironmentPreview(execution)
        case .presentEnvironmentCard:
            guard openWindow(
                id: AppModel.senseZoneVolumeID,
                execution: execution
            ) else { return }
            _ = complete(execution, outcome: .succeeded)
        case .normalizeStoppedSpatialPlayback(let keepsEnvironmentOpen):
            guard openWindow(id: "main", execution: execution) else { return }
            if keepsEnvironmentOpen {
                guard setFullImmersion(false, execution: execution) else { return }
            } else {
                guard await dismissImmersiveSpace(execution: execution) else { return }
            }
            let resolution = complete(execution, outcome: .succeeded)
            if resolution == .effectCompleted {
                _ = dismissWindow(
                    id: "playerControls",
                    execution: execution,
                    phase: .settledRequest
                )
            }
        case .normalizeInvalidatedSpatialPlayback(let keepsEnvironmentOpen):
            await normalizeInvalidatedSpatialPlayback(
                execution,
                keepsEnvironmentOpen: keepsEnvironmentOpen
            )
        }
    }

    private func normalizeInvalidatedSpatialPlayback(
        _ execution: Execution,
        keepsEnvironmentOpen: Bool
    ) async {
        guard await waitForImmersiveActionLane(execution: execution),
              openWindow(id: "main", execution: execution),
              setFullImmersion(false, execution: execution) else {
            return
        }
        if keepsEnvironmentOpen == false {
            guard await dismissImmersiveSpace(execution: execution) else {
                return
            }
        }
        let resolution = complete(execution, outcome: .succeeded)
        if resolution == .effectCompleted {
            _ = dismissWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
            )
        }
    }

    private func presentSpatialPlayback(
        _ presentation: PlaybackPresentation,
        execution: Execution
    ) async {
        guard setFullImmersion(true, execution: execution),
              await yieldExecution(execution),
              let openDisposition = await openImmersiveSpaceIfNeeded(
                execution: execution
              ) else {
            return
        }
        guard openDisposition != .unavailable else {
            _ = complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        guard let settled = await waitUntilPresentationSettled(
            to: presentation,
            execution: execution
        ) else {
            return
        }
        guard settled else {
            if openDisposition == .preexisting {
                guard setFullImmersion(false, execution: execution) else { return }
            } else {
                guard await dismissImmersiveSpace(execution: execution) else {
                    return
                }
            }
            guard setRuntimeError(
                "The spatial playback surface could not attach to PlaybackCore.",
                execution: execution
            ) else { return }
            _ = complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }

        let resolution = complete(execution, outcome: .succeeded)
        guard resolution == .presentationCommitted(presentation),
              openWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
              ) else {
            return
        }
        _ = dismissWindow(
            id: "main",
            execution: execution,
            phase: .settledRequest
        )
    }

    private func recoverSpatialPlayback(
        _ presentation: PlaybackPresentation,
        execution: Execution
    ) async {
        guard setFullImmersion(true, execution: execution),
              await yieldExecution(execution),
              let openDisposition = await openImmersiveSpaceIfNeeded(
                execution: execution
              ) else {
            return
        }
        guard openDisposition != .unavailable else {
            settleFailedRecovery(
                execution,
                failure: .immersiveSpaceUnavailable
            )
            return
        }
        guard let settled = await waitUntilPresentationSettled(
            to: presentation,
            execution: execution
        ) else {
            return
        }
        guard settled else {
            guard await dismissImmersiveSpace(execution: execution),
                  setRuntimeError(
                    "The spatial playback surface could not be restored.",
                    execution: execution
                  ) else {
                return
            }
            settleFailedRecovery(
                execution,
                failure: .spatialPlaybackSurfaceUnavailable
            )
            return
        }

        let resolution = complete(execution, outcome: .succeeded)
        guard resolution == .spatialRecoveryCompleted(presentation),
              openWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
              ) else {
            return
        }
        _ = dismissWindow(
            id: "main",
            execution: execution,
            phase: .settledRequest
        )
    }

    private func settleFailedRecovery(
        _ execution: Execution,
        failure: SpatialPlatformEffectFailure
    ) {
        guard setFullImmersion(false, execution: execution) else { return }
        let resolution = complete(execution, outcome: .failed(failure))
        guard case .spatialRecoveryFailed = resolution,
              openWindow(
                id: "main",
                execution: execution,
                phase: .settledRequest
              ) else {
            return
        }
        _ = dismissWindow(
            id: "playerControls",
            execution: execution,
            phase: .settledRequest
        )
    }

    private func presentWindowPlayback(
        execution: Execution,
        keepsEnvironmentOpen: Bool,
        immersiveSpaceAlreadyClosed: Bool
    ) async {
        guard detachPlaybackSurface(execution: execution),
              let rendererReleased = await waitUntilRendererConsumerIsReleased(
                execution: execution
              ) else {
            return
        }
        guard rendererReleased else {
            let message = immersiveSpaceAlreadyClosed
                ? "The dismissed spatial surface could not release the video renderer."
                : "The spatial playback surface could not release the video renderer."
            guard setRuntimeError(message, execution: execution) else { return }
            _ = complete(
                execution,
                outcome: .failed(.rendererReleaseUnavailable)
            )
            return
        }

        guard openWindow(id: "main", execution: execution) else { return }
        if keepsEnvironmentOpen {
            guard setFullImmersion(false, execution: execution),
                  await yieldExecution(execution) else {
                return
            }
        }
        guard let settled = await waitUntilPresentationSettled(
            to: .window,
            execution: execution
        ) else {
            return
        }
        guard settled else {
            guard setFullImmersion(true, execution: execution),
                  dismissWindow(id: "main", execution: execution) else {
                return
            }
            let message = immersiveSpaceAlreadyClosed
                ? "The window playback surface could not become ready after spatial dismissal."
                : "The window playback surface could not become ready."
            guard setRuntimeError(message, execution: execution) else { return }
            _ = complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }

        if keepsEnvironmentOpen == false,
           immersiveSpaceAlreadyClosed == false,
           await dismissImmersiveSpace(execution: execution) == false {
            return
        }
        let resolution = complete(execution, outcome: .succeeded)
        if case .presentationCommitted(.window) = resolution {
            _ = dismissWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
            )
        }
    }

    private func presentEnvironmentPreview(_ execution: Execution) async {
        guard setFullImmersion(false, execution: execution),
              await yieldExecution(execution) else {
            return
        }
        guard let openDisposition = await openImmersiveSpaceIfNeeded(
            execution: execution
        ) else {
            return
        }
        guard openDisposition != .unavailable else {
            _ = complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        _ = complete(execution, outcome: .succeeded)
    }

    private func dismissEnvironmentPreview(_ execution: Execution) async {
        guard await dismissImmersiveSpace(execution: execution) else { return }
        _ = complete(execution, outcome: .succeeded)
    }

    // MARK: - Guarded platform operations

    private func executionIsLive(
        _ execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard Task.isCancelled == false,
              leaseRegistry.isLive(execution.lease) else {
            return false
        }
        if phase == .currentRequest {
            guard appModel.isSpatialPlatformEffectCurrent(
                execution.request.id,
                executionID: execution.lease.executionID
            ) else {
                return false
            }
        }
        if let mediaSessionID = execution.lease.mediaSessionID,
           playbackRuntime.activeSessionID != mediaSessionID {
            if phase == .currentRequest {
                invalidateExecutionForMediaSessionChange(execution.lease)
            }
            return false
        }
        return true
    }

    private func setFullImmersion(
        _ full: Bool,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase) else { return false }
        guard appModel.platformPrefersFullImmersion != full else { return true }
        markVisibleSpatialSideEffect(execution)
        appModel.setPlatformPrefersFullImmersion(full)
        return true
    }

    private func openWindow(
        id: String,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase) else { return false }
        markVisibleSpatialSideEffect(execution)
        execution.actions.openWindow(id: id)
        return true
    }

    private func dismissWindow(
        id: String,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase) else { return false }
        markVisibleSpatialSideEffect(execution)
        execution.actions.dismissWindow(id: id)
        return true
    }

    private func detachPlaybackSurface(execution: Execution) -> Bool {
        guard executionIsLive(execution) else { return false }
        markVisibleSpatialSideEffect(execution)
        playbackRuntime.detach()
        return true
    }

    private func setRuntimeError(
        _ message: String,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase) else { return false }
        playbackRuntime.lastErrorMessage = message
        return true
    }

    private func yieldExecution(_ execution: Execution) async -> Bool {
        guard executionIsLive(execution) else { return false }
        await Task.yield()
        return executionIsLive(execution)
    }

    private func openImmersiveSpaceIfNeeded(
        execution: Execution
    ) async -> ImmersiveOpenDisposition? {
        let pendingDisposition: ImmersiveOpenDisposition? =
            await performSerializedImmersiveAction(
            execution: execution,
            operation: {
                let residency =
                    self.platformImmersiveSpaceResidency
                    ?? self.appModel.immersiveSpaceResidency
                if residency == .open {
                    self.platformImmersiveSpaceResidency = .open
                    return self.immersiveRequestProvenance.provenance(
                        for: execution.request.id,
                        observingOpenSpace: true
                    ) == .openedByRequest
                        ? .openedByRequest
                        : .preexisting
                }
                self.markVisibleSpatialSideEffect(execution)
                let result = await execution.actions.openImmersiveSpace(
                    id: self.appModel.immersiveSpaceID
                )
                guard case .opened = result else {
                    return .unavailable
                }
                self.platformImmersiveSpaceResidency = .open
                if self.appModel.pendingSpatialPlatformEffect?.id
                    == execution.request.id {
                    self.immersiveRequestProvenance.recordOpenedSpace(
                        for: execution.request.id
                    )
                }
                return .openedByRequest
            }
        )
        guard let disposition = pendingDisposition else {
            return nil
        }
        guard executionIsLive(execution) else { return nil }
        return disposition
    }

    private func dismissImmersiveSpace(execution: Execution) async -> Bool {
        guard await performSerializedImmersiveAction(
            execution: execution,
            operation: {
                let residency =
                    self.platformImmersiveSpaceResidency
                    ?? self.appModel.immersiveSpaceResidency
                guard residency == .open else { return }
                self.markVisibleSpatialSideEffect(execution)
                await execution.actions.dismissImmersiveSpace()
                self.platformImmersiveSpaceResidency = .closed
            }
        ) != nil else {
            return false
        }
        return executionIsLive(execution)
    }

    private func waitForImmersiveActionLane(execution: Execution) async -> Bool {
        guard await performSerializedImmersiveAction(
            execution: execution,
            operation: {}
        ) != nil else {
            return false
        }
        return executionIsLive(execution)
    }

    private func markVisibleSpatialSideEffect(_ execution: Execution) {
        guard executionProgress[execution.lease.executionID] != nil else { return }
        executionProgress[execution.lease.executionID]?
            .didIssueVisibleSpatialSideEffect = true
    }

    private func performSerializedImmersiveAction<Result: Sendable>(
        execution: Execution,
        operation: @escaping @MainActor () async -> Result
    ) async -> Result? {
        guard let result = await immersiveActionLane.perform(
            isLive: { [weak self] in
                self?.executionIsLive(execution) == true
            },
            operation: operation
        ) else {
            return nil
        }
        guard executionIsLive(execution) else { return nil }
        return result
    }

    private func waitUntilPresentationSettled(
        to presentation: PlaybackPresentation,
        execution: Execution
    ) async -> Bool? {
        guard executionIsLive(execution) else { return nil }
        let settled = await playbackRuntime.waitUntilPresentationSettled(
            to: presentation
        )
        guard executionIsLive(execution) else { return nil }
        return settled
    }

    private func waitUntilRendererConsumerIsReleased(
        execution: Execution
    ) async -> Bool? {
        guard executionIsLive(execution) else { return nil }
        let released = await playbackRuntime.waitUntilRendererConsumerIsReleased()
        guard executionIsLive(execution) else { return nil }
        return released
    }

    private func executePlaybackTransport(
        _ intent: SpatialPlaybackTransportIntent,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> GuardedTransportResult {
        guard executionIsLive(execution, phase: phase) else {
            return .invalidated
        }
        do {
            try playbackRuntime.performSpatialPlaybackTransport(intent)
            guard executionIsLive(execution, phase: phase) else {
                return .invalidated
            }
            return .succeeded
        } catch {
            let reason: SpatialPlaybackTransportFailureReason =
                playbackRuntime.activeSessionID == intent.mediaSessionID
                    ? .operationRejected
                    : .mediaSessionChanged
            return .failed(
                reason: reason,
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Execution settlement

    @discardableResult
    private func complete(
        _ execution: Execution,
        outcome: SpatialPlatformEffectOutcome,
        performsAfterTransport: Bool = true
    ) -> SpatialPlatformEffectResolution {
        guard executionIsLive(execution) else { return .ignored }
        let resolution = appModel.receiveSpatialPlatformResult(
            .effectCompleted(
                SpatialPlatformEffectResult(
                    requestID: execution.request.id,
                    executionID: execution.lease.executionID,
                    mediaSessionID:
                        execution.request.playbackTransportPlan?.mediaSessionID,
                    outcome: outcome
                )
            )
        )
        if resolution != .ignored {
            immersiveRequestProvenance.clear(requestID: execution.request.id)
        }
        guard resolution != .ignored,
              performsAfterTransport,
              outcome != .failed(.mediaSessionChanged) else {
            return resolution
        }

        let transportIntent: SpatialPlaybackTransportIntent?
        switch outcome {
        case .succeeded:
            transportIntent =
                execution.request.playbackTransportPlan?.afterSuccess
        case .failed:
            transportIntent =
                execution.request.playbackTransportPlan?.afterFailure
        }
        guard let transportIntent else { return resolution }

        switch executePlaybackTransport(
            transportIntent,
            execution: execution,
            phase: .settledRequest
        ) {
        case .succeeded, .invalidated:
            break
        case .failed(let reason, let message):
            guard reason != .mediaSessionChanged,
                  setRuntimeError(
                    message,
                    execution: execution,
                    phase: .settledRequest
                  ) else {
                return resolution
            }
            appModel.receiveSpatialPlatformResult(
                .playbackTransportFailed(
                    SpatialPlaybackTransportFailure(
                        requestID: execution.request.id,
                        executionID: execution.lease.executionID,
                        mediaSessionID: transportIntent.mediaSessionID,
                        intent: transportIntent,
                        reason: reason
                    )
                )
            )
        }
        return resolution
    }
}

@MainActor
struct SpatialPlatformEffectExecutor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SpatialPlatformEffectCoordinator.self) private var coordinator
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var registrationID = UUID()

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                coordinator.register(
                    id: registrationID,
                    openImmersiveSpace: openImmersiveSpace,
                    dismissImmersiveSpace: dismissImmersiveSpace,
                    openWindow: openWindow,
                    dismissWindow: dismissWindow
                )
            }
            .onDisappear {
                coordinator.unregister(id: registrationID)
            }
            .onChange(of: appModel.pendingSpatialPlatformEffect?.id, initial: true) { _, _ in
                coordinator.requestDrain()
            }
    }
}
#endif
