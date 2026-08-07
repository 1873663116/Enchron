import Foundation
import Observation
import OSLog
import PlaybackFeature
import PlaybackPresentation
import SwiftUI
import UIKit

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
    private let logger = Logger(
        subsystem: "app.enchron",
        category: "SpatialPlatformEffect"
    )

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
    private var immersiveSpaceObservation =
        SpatialPlatformImmersiveSpaceObservation()
    @ObservationIgnored
    private var windowObservation = SpatialPlatformWindowObservation()
    @ObservationIgnored
    private weak var mainWindowScene: UIWindowScene?

    private(set) var lastPlatformOperation = "none"
    private(set) var lastExecutionCheckpoint = "none"
    private(set) var executionAttemptCount: UInt64 = 0
    private(set) var lastExecutionResolution = "none"

    private static let immersiveSpaceLifecycleConfirmationTimeout =
        Duration.seconds(5)
    private static let windowLifecycleConfirmationTimeout = Duration.seconds(5)
    private static let progressiveModeRequestApplicationTimeout = Duration.seconds(5)
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
        lastPlatformOperation = "executor-registered"
        requestDrain()
    }

    func unregister(id: UUID) {
        if let invalidatedLease = leaseRegistry.unregister(id: id) {
            invalidateTask(invalidatedLease)
        }
        lastPlatformOperation = "executor-unregistered"
        requestDrain()
    }

    var registeredPlatformExecutorCount: Int {
        leaseRegistry.registeredCapabilityCount
    }

    var mainWindowObservedResidency: String {
        windowObservation.residency(for: .main).map(String.init(describing:))
            ?? "unobserved"
    }

    var mainWindowObservationRevision: UInt64 {
        windowObservation.revision(for: .main)
    }

    var playerControlsWindowObservedResidency: String {
        windowObservation.residency(for: .playerControls)
            .map(String.init(describing:)) ?? "unobserved"
    }

    var playerControlsWindowObservationRevision: UInt64 {
        windowObservation.revision(for: .playerControls)
    }

    func recordImmersiveSpaceResidency(
        _ residency: SpatialPlatformImmersiveSpaceResidency
    ) {
        immersiveSpaceObservation.record(residency)
        let residencyDescription = String(describing: residency)
        logger.info(
            """
            Immersive Space lifecycle observed \
            residency=\(residencyDescription, privacy: .public) \
            revision=\(self.immersiveSpaceObservation.revision, privacy: .public)
            """
        )
    }

    func recordWindowResidency(
        _ residency: SpatialPlatformWindowResidency,
        for window: SpatialPlatformWindowIdentity
    ) {
        windowObservation.record(residency, for: window)
        let residencyDescription = String(describing: residency)
        logger.info(
            """
            Window lifecycle observed window=\(window.rawValue, privacy: .public) \
            residency=\(residencyDescription, privacy: .public) \
            revision=\(self.windowObservation.revision(for: window), privacy: .public)
            """
        )
    }

    func recordMainWindowScene(_ windowScene: UIWindowScene?) {
        mainWindowScene = windowScene
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
        lastExecutionCheckpoint = "execution-invalidated"
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
        lastExecutionCheckpoint = "execution-finish-entered"
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
        lastExecutionCheckpoint = "execution-finished"
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
            || immersiveSpaceObservation.residency == .open
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
        executionAttemptCount &+= 1
        lastExecutionCheckpoint = "execution-started"
        lastPlatformOperation = "effect-execution-started"

        if let beforeEffect = execution.request.playbackTransportPlan?.beforeEffect {
            lastPlatformOperation = "before-effect-transport-started"
            switch await executePlaybackTransport(beforeEffect, execution: execution) {
            case .succeeded:
                lastExecutionCheckpoint = "before-effect-transport-completed"
                lastPlatformOperation = "before-effect-transport-completed"
                break
            case .invalidated:
                return
            case .failed(let reason, let message):
                guard setRuntimeError(message, execution: execution) else { return }
                if reason == .mediaSessionChanged {
                    invalidateExecutionForMediaSessionChange(execution.lease)
                } else {
                    _ = await complete(
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
            await presentSpatialPlayback(
                presentation,
                execution: execution
            )
        case .recoverSpatialPlayback(let presentation):
            await recoverSpatialPlayback(presentation, execution: execution)
        case .switchWindowHostedPlayback(let presentation):
            await switchWindowHostedPlayback(presentation, execution: execution)
        case .presentWindowPlayback(
            let presentation,
            let keepsEnvironmentOpen,
            let immersiveSpaceAlreadyClosed
        ):
            await presentWindowPlayback(
                presentation: presentation,
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
            _ = await complete(execution, outcome: .succeeded)
        case .normalizeStoppedSpatialPlayback(let keepsEnvironmentOpen):
            guard openWindow(id: "main", execution: execution) else { return }
            if keepsEnvironmentOpen == false {
                guard await dismissImmersiveSpace(execution: execution) else { return }
            }
            let resolution = await complete(execution, outcome: .succeeded)
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
              openWindow(id: "main", execution: execution) else {
            return
        }
        if keepsEnvironmentOpen == false {
            guard await dismissImmersiveSpace(execution: execution) else {
                return
            }
        }
        let resolution = await complete(execution, outcome: .succeeded)
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
        guard await yieldExecution(execution) else { return }
        guard let progressiveModeRequestApplied = await waitUntilProgressiveModeRequestIsApplied(
                isRequired:
                    execution.request.requiresProgressiveModeRequestBeforePanoramaTransfer,
                execution: execution
              ) else {
            return
        }
        guard progressiveModeRequestApplied else {
            guard setRuntimeError(
                "The video component did not accept the progressive viewing request before the Panorama transfer.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.immersiveViewingModeUnavailable)
            )
            return
        }
        guard let openDisposition = await openImmersiveSpaceIfNeeded(
                execution: execution
              ) else {
            return
        }
        guard openDisposition != .unavailable else {
            _ = await complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        guard await waitUntilPresentationTransitionTime(
            PlaybackPresentationTransitionAppearance.rendererTransferDelay,
            execution: execution
        ), appModel.allowPresentationSourceRendererRelease() else {
            return
        }
        guard let rendererReleased = await waitUntilRendererConsumerIsReleased(
                from: appModel.presentationTransition?.previousPresentation,
                execution: execution
              ) else {
            return
        }
        guard rendererReleased else {
            if openDisposition != .preexisting {
                guard await dismissImmersiveSpace(execution: execution) else {
                    return
                }
            }
            _ = await complete(
                execution,
                outcome: .failed(.rendererReleaseUnavailable)
            )
            return
        }
        guard let settled = await waitUntilPresentationSettled(
            to: presentation,
            execution: execution
        ) else {
            lastExecutionCheckpoint = "spatial-settlement-execution-invalidated"
            return
        }
        lastExecutionCheckpoint = settled
            ? "spatial-settlement-confirmed"
            : "spatial-settlement-rejected"
        guard settled else {
            lastPlatformOperation = "spatial-surface-settlement-failed"
            if openDisposition != .preexisting {
                guard await dismissImmersiveSpace(execution: execution) else {
                    return
                }
            }
            guard setRuntimeError(
                "The spatial playback surface could not attach to PlaybackCore.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }
        lastPlatformOperation = "spatial-surface-settled"
        guard await dismissEnvironmentCardIfNeeded(execution: execution),
              await openWindowAndWaitForAppearance(
                .playerControls,
                execution: execution
              ) else {
            guard executionIsLive(execution) else { return }
            _ = dismissWindow(id: "playerControls", execution: execution)
            if openDisposition != .preexisting {
                guard await dismissImmersiveSpace(execution: execution) else {
                    return
                }
            }
            guard setRuntimeError(
                "The Player Controls Window could not become usable.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.playerControlsWindowUnavailable)
            )
            return
        }
        guard await waitUntilPresentationTransitionTime(
            PlaybackPresentationTransitionAppearance.sourceFadeDuration,
            execution: execution
        ) else { return }
        let resolution = await complete(execution, outcome: .succeeded)
        guard resolution == .presentationCommitted(presentation) else {
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
        guard await yieldExecution(execution),
              let rendererReleased = await waitUntilRendererConsumerIsReleased(
                execution: execution
              ) else {
            return
        }
        guard rendererReleased else {
            await settleFailedRecovery(
                execution,
                failure: .rendererReleaseUnavailable
            )
            return
        }
        guard let openDisposition = await openImmersiveSpaceIfNeeded(
                execution: execution
              ) else {
            return
        }
        guard openDisposition != .unavailable else {
            await settleFailedRecovery(
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
            await settleFailedRecovery(
                execution,
                failure: .spatialPlaybackSurfaceUnavailable
            )
            return
        }

        guard await dismissEnvironmentCardIfNeeded(execution: execution),
              await openWindowAndWaitForAppearance(
                .playerControls,
                execution: execution
              ) else {
            guard executionIsLive(execution) else { return }
            await settleFailedRecovery(
                execution,
                failure: .playerControlsWindowUnavailable
            )
            return
        }
        let resolution = await complete(execution, outcome: .succeeded)
        guard resolution == .spatialRecoveryCompleted(presentation) else { return }
        _ = dismissWindow(
            id: "main",
            execution: execution,
            phase: .settledRequest
        )
    }

    private func settleFailedRecovery(
        _ execution: Execution,
        failure: SpatialPlatformEffectFailure
    ) async {
        let resolution = await complete(execution, outcome: .failed(failure))
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
        presentation: PlaybackPresentation,
        execution: Execution,
        keepsEnvironmentOpen: Bool,
        immersiveSpaceAlreadyClosed: Bool
    ) async {
        lastPlatformOperation = "window-return-started"
        guard openWindow(id: "main", execution: execution),
              await waitUntilPresentationTransitionTime(
                PlaybackPresentationTransitionAppearance.rendererTransferDelay,
                execution: execution
              ),
              appModel.allowPresentationSourceRendererRelease(),
              detachPlaybackSurface(execution: execution),
              let rendererReleased = await waitUntilRendererConsumerIsReleased(
                from: appModel.presentationTransition?.previousPresentation,
                execution: execution
              ) else {
            return
        }
        guard rendererReleased else {
            lastPlatformOperation = "renderer-release-failed"
            let message = immersiveSpaceAlreadyClosed
                ? "The dismissed spatial surface could not release the video renderer."
                : "The spatial playback surface could not release the video renderer."
            guard setRuntimeError(message, execution: execution) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.rendererReleaseUnavailable)
            )
            return
        }

        if keepsEnvironmentOpen == false,
           immersiveSpaceAlreadyClosed == false,
           await dismissImmersiveSpace(execution: execution) == false {
            lastPlatformOperation = "immersive-space-dismiss-failed"
            return
        }

        lastPlatformOperation = "main-window-requested"

        guard await openWindowAndWaitForAppearance(
            .main,
            execution: execution
        ) else {
            lastPlatformOperation = "main-window-appearance-failed"
            guard executionIsLive(execution) else { return }
            _ = dismissWindow(id: "main", execution: execution)
            guard setRuntimeError(
                "The Main Window could not become usable.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.mainWindowUnavailable)
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
            lastPlatformOperation = "window-playback-surface-failed"
            guard dismissWindow(id: "main", execution: execution) else {
                return
            }
            let message = immersiveSpaceAlreadyClosed
                ? "The window playback surface could not become ready after spatial dismissal."
                : "The window playback surface could not become ready."
            guard setRuntimeError(message, execution: execution) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }

        guard await orderWindowToFront(.main, execution: execution) else {
            lastPlatformOperation = "main-window-activation-failed"
            return
        }
        guard await waitUntilPresentationTransitionTime(
            PlaybackPresentationTransitionAppearance.sourceFadeDuration,
            execution: execution
        ) else { return }
        let resolution = await complete(execution, outcome: .succeeded)
        if case .presentationCommitted(.window) = resolution {
            lastPlatformOperation = "window-return-completed"
            if playbackRuntime.effectiveContentIsPanoramic == false {
                _ = dismissWindow(
                    id: "playerControls",
                    execution: execution,
                    phase: .settledRequest
                )
            }
        }
    }

    private func switchWindowHostedPlayback(
        _ presentation: PlaybackPresentation,
        execution: Execution
    ) async {
        let controlsReady: Bool
        if presentation == .portal {
            controlsReady = await openWindowAndWaitForAppearance(
                .playerControls,
                execution: execution
            )
        } else {
            controlsReady = dismissWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
            )
        }
        guard controlsReady else { return }
        _ = await complete(execution, outcome: .succeeded)
    }

    private func presentEnvironmentPreview(_ execution: Execution) async {
        guard await yieldExecution(execution) else {
            return
        }
        guard let openDisposition = await openImmersiveSpaceIfNeeded(
            execution: execution
        ) else {
            return
        }
        guard openDisposition != .unavailable else {
            _ = await complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        _ = await complete(execution, outcome: .succeeded)
    }

    private func dismissEnvironmentPreview(_ execution: Execution) async {
        guard await dismissImmersiveSpace(execution: execution) else { return }
        _ = await complete(execution, outcome: .succeeded)
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

    private func openWindow(
        id: String,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase) else { return false }
        markVisibleSpatialSideEffect(execution)
        lastPlatformOperation = "\(id)-window-requested"
        execution.actions.openWindow(id: id)
        return true
    }

    private func openWindowAndWaitForAppearance(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) async -> Bool {
        let observationRevision = windowObservation.revision(for: window)
        guard openWindow(id: window.rawValue, execution: execution) else {
            return false
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            let hasFreshAppearance = windowObservation.confirms(
                .open,
                for: window,
                after: observationRevision
            )
            if hasFreshAppearance
                || windowObservation.residency(for: window) == .open {
                lastPlatformOperation = "\(window.rawValue)-window-appeared"
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        logger.error(
            "Window lifecycle confirmation timed out window=\(window.rawValue, privacy: .public)"
        )
        return false
    }

    private func orderWindowToFront(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) async -> Bool {
        guard openWindow(id: window.rawValue, execution: execution) else {
            return false
        }
        guard window == .main, let mainWindowScene else {
            logger.error(
                "The Main Window scene was unavailable for activation"
            )
            return false
        }
        let request = UISceneSessionActivationRequest(
            session: mainWindowScene.session
        )
        UIApplication.shared.activateSceneSession(for: request) {
            [logger] error in
            logger.error(
                "Main Window activation failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        await Task.yield()
        return executionIsLive(execution)
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

    private func dismissEnvironmentCardIfNeeded(
        execution: Execution
    ) async -> Bool {
        guard appModel.environmentCardResidency != .closed else { return true }
        guard dismissWindow(
            id: AppModel.senseZoneVolumeID,
            execution: execution
        ) else { return false }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while appModel.environmentCardResidency != .closed,
              clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard executionIsLive(execution) else { return false }
        guard appModel.environmentCardResidency == .closed else {
            guard setRuntimeError(
                "The Environment Card could not close before spatial playback.",
                execution: execution
            ) else { return false }
            _ = await complete(
                execution,
                outcome: .failed(.environmentCardDismissalUnavailable)
            )
            return false
        }
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

    private func waitUntilProgressiveModeRequestIsApplied(
        isRequired: Bool,
        execution: Execution
    ) async -> Bool? {
        guard isRequired else { return true }
        guard let transition = appModel.presentationTransition,
              transition.requiresProgressiveModeRequestBeforePanoramaTransfer else {
            return false
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.progressiveModeRequestApplicationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return nil }
            if appModel.progressiveModeRequestIsApplied(for: transition.id) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitUntilPresentationTransitionTime(
        _ elapsedTime: TimeInterval,
        execution: Execution
    ) async -> Bool {
        guard executionIsLive(execution),
              let remaining = appModel.presentationTransitionRemainingTime(
                until: elapsedTime
              ) else {
            return false
        }
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
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
                    self.immersiveSpaceObservation.residency
                    ?? self.appModel.immersiveSpaceResidency
                if residency == .open {
                    return self.immersiveRequestProvenance.provenance(
                        for: execution.request.id,
                        observingOpenSpace: true
                    ) == .openedByRequest
                        ? .openedByRequest
                        : .preexisting
                }
                guard let openingContext = self.immersiveSpaceOpeningContext(
                    for: execution.request.effect
                ) else {
                    return .unavailable
                }
                self.appModel.prepareImmersiveSpaceOpening(
                    initialAmount: SpatialImmersiveSpacePolicy.openingInitialAmount(
                        for: openingContext,
                        lastObservedAmount: self.appModel.lastObservedImmersionAmount
                    )
                )
                await Task.yield()
                guard self.executionIsLive(execution) else {
                    return .unavailable
                }
                let observationRevision = self.immersiveSpaceObservation.revision
                self.markVisibleSpatialSideEffect(execution)
                let result = await execution.actions.openImmersiveSpace(
                    id: self.appModel.immersiveSpaceID
                )
                guard case .opened = result else {
                    return .unavailable
                }
                guard await self.waitForImmersiveSpaceLifecycleObservation(
                    .open,
                    after: observationRevision,
                    execution: execution
                ) else {
                    return .unavailable
                }
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

    private func immersiveSpaceOpeningContext(
        for effect: SpatialPlatformEffect
    ) -> SpatialImmersiveSpaceOpeningContext? {
        switch effect {
        case .presentEnvironmentPreview:
            .environment
        case .presentSpatialPlayback(let presentation),
             .recoverSpatialPlayback(let presentation):
            .playback(presentation)
        case .presentWindowPlayback(_, _, _),
             .switchWindowHostedPlayback,
             .dismissEnvironmentPreview,
             .presentEnvironmentCard,
             .normalizeStoppedSpatialPlayback(_),
             .normalizeInvalidatedSpatialPlayback(_):
            nil
        }
    }

    private func dismissImmersiveSpace(execution: Execution) async -> Bool {
        guard let dismissed = await performSerializedImmersiveAction(
            execution: execution,
            operation: {
                let residency =
                    self.immersiveSpaceObservation.residency
                    ?? self.appModel.immersiveSpaceResidency
                guard residency == .open else { return true }
                let observationRevision = self.immersiveSpaceObservation.revision
                self.markVisibleSpatialSideEffect(execution)
                await execution.actions.dismissImmersiveSpace()
                guard self.executionIsLive(execution) else { return false }

                // The awaited scene action is the platform completion boundary.
                // SwiftUI doesn't guarantee that the ImmersiveSpace content's
                // onDisappear callback runs before that action returns.
                if self.immersiveSpaceObservation.confirms(
                    .closed,
                    after: observationRevision
                ) == false {
                    self.recordCompletedImmersiveSpaceDismissal()
                }
                return true
            }
        ) else {
            return false
        }
        guard dismissed else {
            return false
        }
        return executionIsLive(execution)
    }

    private func recordCompletedImmersiveSpaceDismissal() {
        recordImmersiveSpaceResidency(.closed)
        _ = appModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(nil)
        )
        logger.notice(
            "Immersive Space dismissal action completed before its lifecycle callback"
        )
    }

    private func waitForImmersiveSpaceLifecycleObservation(
        _ residency: SpatialPlatformImmersiveSpaceResidency,
        after revision: UInt64,
        execution: Execution
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.immersiveSpaceLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            if immersiveSpaceObservation.confirms(
                residency,
                after: revision
            ) {
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        let expectedResidency = String(describing: residency)
        let observedResidency = String(describing: immersiveSpaceObservation.residency)
        logger.error(
            """
            Immersive Space lifecycle confirmation timed out \
            expected=\(expectedResidency, privacy: .public) \
            observed=\(observedResidency, privacy: .public)
            """
        )
        return false
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
        from sourcePresentation: PlaybackPresentation? = nil,
        execution: Execution
    ) async -> Bool? {
        guard executionIsLive(execution) else { return nil }
        let released = await playbackRuntime.waitUntilRendererConsumerIsReleased(
            from: sourcePresentation
        )
        guard executionIsLive(execution) else { return nil }
        return released
    }

    private func executePlaybackTransport(
        _ intent: SpatialPlaybackTransportIntent,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) async -> GuardedTransportResult {
        guard executionIsLive(execution, phase: phase) else {
            return .invalidated
        }
        do {
            try await playbackRuntime.performSpatialPlaybackTransport(intent)
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
    ) async -> SpatialPlatformEffectResolution {
        guard executionIsLive(execution) else { return .ignored }
        let presentationRestoredAfterFailure: PlaybackPresentation? = switch outcome {
        case .succeeded:
            nil
        case .failed:
            switch execution.request.effect {
            case .presentSpatialPlayback, .presentWindowPlayback, .switchWindowHostedPlayback:
                appModel.presentationTransition?.previousPresentation
            default:
                nil
            }
        }
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
        lastExecutionResolution = "\(String(describing: outcome))-\(String(describing: resolution))"
        lastExecutionCheckpoint = "effect-completed-\(String(describing: outcome))-\(String(describing: resolution))"
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

        if let presentationRestoredAfterFailure {
            let restored = await playbackRuntime.waitUntilPresentationSettled(
                to: presentationRestoredAfterFailure
            )
            guard executionIsLive(execution, phase: .settledRequest), restored else {
                return resolution
            }
        }

        switch await executePlaybackTransport(
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
