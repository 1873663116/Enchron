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
    private let stopPlaybackForFailedPresentationTransfer: @MainActor () async -> Void
    @ObservationIgnored
    private let persistSettledPlaybackMode: @MainActor (PlaybackPresentation) -> Void
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
    private var observedPlayerControlsSceneIdentity: PlayerControlsSceneIdentity?
    @ObservationIgnored
    private weak var mainWindowScene: UIWindowScene?

    private(set) var lastPlatformOperation = "none"
    private(set) var lastExecutionCheckpoint = "none"
    private(set) var executionAttemptCount: UInt64 = 0
    private(set) var lastExecutionResolution = "none"

    private static let immersiveSpaceLifecycleConfirmationTimeout =
        Duration.seconds(5)
    private static let windowLifecycleConfirmationTimeout = Duration.seconds(5)
    init(
        appModel: AppModel,
        playbackRuntime: PlaybackRuntime,
        stopPlaybackForFailedPresentationTransfer: (@MainActor () async -> Void)? = nil,
        persistSettledPlaybackMode: (@MainActor (PlaybackPresentation) -> Void)? = nil
    ) {
        self.appModel = appModel
        self.playbackRuntime = playbackRuntime
        self.stopPlaybackForFailedPresentationTransfer =
            stopPlaybackForFailedPresentationTransfer
            ?? { await playbackRuntime.stopAndWait() }
        self.persistSettledPlaybackMode = persistSettledPlaybackMode ?? { _ in }
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

    /// Player Controls is a multi-instance WindowGroup during presentation
    /// handoff. A stale source Scene closing must not overwrite the residency
    /// of the newly active target controls Scene.
    func recordPlayerControlsWindowResidency(
        _ residency: SpatialPlatformWindowResidency,
        identity: PlayerControlsSceneIdentity
    ) {
        switch residency {
        case .open:
            observedPlayerControlsSceneIdentity = identity
            recordWindowResidency(.open, for: .playerControls)
        case .closed:
            guard observedPlayerControlsSceneIdentity == identity else { return }
            observedPlayerControlsSceneIdentity = nil
            recordWindowResidency(.closed, for: .playerControls)
        }
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
            lease: claim.lease
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
        case .presentInitialSpatialPlayback(let presentation):
            await presentInitialSpatialPlayback(
                presentation,
                execution: execution
            )
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

    private func presentInitialSpatialPlayback(
        _ presentation: PlaybackPresentation,
        execution: Execution
    ) async {
        lastExecutionCheckpoint = "initial-spatial-scene-and-session-wait-started"
        let openDisposition = await openImmersiveSpaceIfNeeded(execution: execution)
        guard let openDisposition, openDisposition != .unavailable else {
            guard executionIsLive(execution) else { return }
            lastExecutionCheckpoint =
                "initial-spatial-scene-unavailable:immersive=\(String(describing: openDisposition))"
            _ = await complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        async let mainWindowClosed = dismissWindowAndWaitForDisappearance(
            .main,
            execution: execution
        )
        _ = dismissWindow(id: "playerControls", execution: execution)
        lastExecutionCheckpoint = "initial-spatial-scene-open-awaiting-surface"
        guard await waitUntilPresentationSettled(
            to: presentation,
            execution: execution,
            allowsPendingSessionStart: true
        ) == true else {
            guard executionIsLive(execution) else { return }
            lastExecutionCheckpoint = [
                "initial-spatial-surface-rejected",
                "preparation=\(appModel.spatialPlaybackSurfacePreparationStage)",
                "attached=\(String(describing: playbackRuntime.attachedPresentation))",
                "lifecycle=\(playbackRuntime.productLifecycle.rawValue)"
            ].joined(separator: ",")
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }
        guard await mainWindowClosed else {
            guard executionIsLive(execution) else { return }
            lastExecutionCheckpoint = "initial-spatial-main-window-did-not-close"
            _ = await complete(
                execution,
                outcome: .failed(.mainWindowUnavailable)
            )
            return
        }
        let resolution = await complete(execution, outcome: .succeeded)
        if resolution == .effectCompleted {
            persistSettledPlaybackMode(presentation)
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
        guard await yieldExecution(execution) else {
            return
        }

        // Assemble the target decoder concurrently with opening the target
        // Scene. Neither operation changes what the wearer sees yet.
        let replacementTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime
                .prepareTechnicalSessionForPresentationConversion()
        }
        let openDispositionTask = Task { @MainActor in
            await openImmersiveSpaceIfNeeded(execution: execution)
        }

        guard let openDisposition = await openDispositionTask.value else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
        }
        guard openDisposition != .unavailable else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            _ = await complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        guard await dismissEnvironmentCardIfNeeded(execution: execution) else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
        }
        do {
            try await replacementTask.value
        } catch {
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The Panorama RealityView could not assemble its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else {
                return
            }
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }

        guard appModel.allowPresentationSourceRendererRelease() else {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
        }
        do {
            try playbackRuntime.activatePreparedTechnicalSessionReplacement()
        } catch {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The Panorama RealityView could not activate its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }
        guard appModel.allowPresentationTargetRendererBinding() else {
            return
        }

        // Avoid two audible/decoding sessions while the hidden target advances
        // to its first presentable frame. The old Entity keeps its last image.
        playbackRuntime.pauseDepartingTechnicalSessionForVisualCutover()
        guard await restoreTargetPlaybackIntentBeforeSettlement(execution) else {
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

        // This is the only visible boundary: reveal Panorama, fade the complete
        // Window content, and ask visionOS to dismiss that Window together.
        guard appModel.beginPresentationVisualCutover() else { return }
        async let mainWindowClosed = dismissWindowAndWaitForDisappearance(
            .main,
            execution: execution
        )
        _ = dismissWindow(id: "playerControls", execution: execution)
        guard await mainWindowClosed else {
            guard setRuntimeError(
                "The Main Window could not disappear during the Panorama cutover.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.mainWindowUnavailable)
            )
            return
        }
        appModel.finishPresentationVisualCutover()
        await playbackRuntime.retireDepartingTechnicalSessionAfterSceneDisappearance()
        let resolution = await complete(execution, outcome: .succeeded)
        guard resolution == .presentationCommitted(presentation) else {
            return
        }
        persistSettledPlaybackMode(presentation)
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

        guard await dismissEnvironmentCardIfNeeded(execution: execution) else { return }
        let resolution = await complete(execution, outcome: .succeeded)
        guard resolution == .spatialRecoveryCompleted(presentation) else { return }
        persistSettledPlaybackMode(presentation)
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
        guard executionIsLive(execution),
              appModel.allowPresentationSourceRendererRelease(),
              detachPlaybackSurface(execution: execution) else {
            return
        }

        let replacementTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime
                .rebuildTechnicalSessionForPresentationConversion()
        }
        async let windowReady = openWindowAndWaitForAppearance(
            .main,
            execution: execution
        )
        async let fadeCompleted = waitUntilPresentationTransitionTime(
            PlaybackPresentationTransitionAppearance.sourceFadeDuration,
            execution: execution
        )
        _ = dismissWindow(id: "playerControls", execution: execution)

        guard await fadeCompleted,
              let rendererReleased = await waitUntilRendererConsumerIsReleased(
                from: appModel.presentationTransition?.previousPresentation,
                execution: execution
              ) else {
            replacementTask.cancel()
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
            replacementTask.cancel()
            lastPlatformOperation = "immersive-space-dismiss-failed"
            return
        }

        guard appModel.allowPresentationTargetRendererBinding() else {
            replacementTask.cancel()
            return
        }

        lastPlatformOperation = "main-window-requested"

        guard await windowReady else {
            replacementTask.cancel()
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
        do {
            try await replacementTask.value
        } catch {
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The Window could not assemble its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }
        guard await restoreTargetPlaybackIntentBeforeSettlement(execution) else {
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
        let resolution = await complete(execution, outcome: .succeeded)
        if case .presentationCommitted(let committedPresentation) = resolution {
            persistSettledPlaybackMode(committedPresentation)
        }
        if case .presentationCommitted(.window) = resolution {
            lastPlatformOperation = "window-return-completed"
            _ = dismissWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
            )
        }
    }

    private func switchWindowHostedPlayback(
        _ presentation: PlaybackPresentation,
        execution: Execution
    ) async {
        _ = dismissWindow(id: "playerControls", execution: execution)
        let replacementTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime
                .rebuildTechnicalSessionForPresentationConversion()
        }
        do {
            try await replacementTask.value
        } catch {
            guard setRuntimeError(
                "The Window could not assemble its replacement playback session: \(error.localizedDescription)",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }
        guard await restoreTargetPlaybackIntentBeforeSettlement(execution) else {
            return
        }
        guard await waitUntilPresentationSettled(
            to: presentation,
            execution: execution
        ) == true else { return }
        let resolution = await complete(execution, outcome: .succeeded)
        if case .presentationCommitted(let committedPresentation) = resolution {
            persistSettledPlaybackMode(committedPresentation)
        }
        if case .presentationCommitted(.window) = resolution {
            _ = dismissWindow(
                id: "playerControls",
                execution: execution,
                phase: .settledRequest
            )
        }
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
        guard executionIsLive(execution, phase: phase),
              let actions = leaseRegistry.currentCapability else { return false }
        markVisibleSpatialSideEffect(execution)
        lastPlatformOperation = "\(id)-window-requested"
        switch id {
        case SpatialPlatformWindowIdentity.main.rawValue:
            let identity = appModel.activePlaybackWindowSceneIdentity
                ?? appModel.beginFreshPlaybackWindowScene()
            actions.openWindow(id: id, value: identity)
        case SpatialPlatformWindowIdentity.playerControls.rawValue:
            let identity = appModel.activePlayerControlsSceneIdentity
                ?? appModel.beginFreshPlayerControlsScene()
            actions.openWindow(id: id, value: identity)
        default:
            actions.openWindow(id: id)
        }
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
        // A freshly created WindowGroup instance is already the foreground
        // result of openWindow. Re-activating its UIKit scene caused a system
        // presentation crash on visionOS and provides no additional contract.
        guard windowObservation.residency(for: window) == .open else {
            return false
        }
        return executionIsLive(execution)
    }

    private func dismissWindow(
        id: String,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase),
              let actions = leaseRegistry.currentCapability else { return false }
        markVisibleSpatialSideEffect(execution)
        switch id {
        case SpatialPlatformWindowIdentity.main.rawValue:
            actions.dismissWindow(id: id)
        case SpatialPlatformWindowIdentity.playerControls.rawValue:
            guard let identity = appModel.activePlayerControlsSceneIdentity else {
                return windowObservation.residency(for: .playerControls) != .open
            }
            actions.dismissWindow(id: id, value: identity)
        default:
            actions.dismissWindow(id: id)
        }
        return true
    }

    /// A renderer cannot cross RealityView roots until UIKit disconnects the
    /// source Window Scene. Runtime ownership release is necessary but does not
    /// prove that RealityKit removed its asynchronous video target. SwiftUI's
    /// root `onDisappear` is not a Window lifecycle contract on visionOS.
    private func dismissWindowAndWaitForDisappearance(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) async -> Bool {
        let observationRevision = windowObservation.revision(for: window)
        let dismissedSceneSessionIdentifier = window == .main
            ? mainWindowScene?.session.persistentIdentifier
            : nil
        guard dismissWindow(id: window.rawValue, execution: execution) else {
            return false
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            if windowObservation.confirms(
                .closed,
                for: window,
                after: observationRevision
            ) {
                lastPlatformOperation = "\(window.rawValue)-window-disappeared"
                return true
            }
            if window == .main,
               mainWindowSceneIsDisconnected(
                sessionIdentifier: dismissedSceneSessionIdentifier
               ) {
                lastPlatformOperation = "main-window-scene-disconnected"
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        logger.error(
            "Window disappearance confirmation timed out window=\(window.rawValue, privacy: .public)"
        )
        return false
    }

    private func mainWindowSceneIsDisconnected(
        sessionIdentifier: String?
    ) -> Bool {
        guard let sessionIdentifier else { return false }
        if mainWindowScene?.activationState == .unattached {
            return true
        }
        return UIApplication.shared.connectedScenes.contains { scene in
            scene.session.persistentIdentifier == sessionIdentifier
        } == false
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
                guard let actions = self.leaseRegistry.currentCapability else {
                    return .unavailable
                }
                let observationRevision = self.immersiveSpaceObservation.revision
                self.markVisibleSpatialSideEffect(execution)
                let result = await actions.openImmersiveSpace(
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
        case .presentInitialSpatialPlayback(let presentation),
             .presentSpatialPlayback(let presentation),
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
                guard let actions = self.leaseRegistry.currentCapability else {
                    return false
                }
                let observationRevision = self.immersiveSpaceObservation.revision
                self.markVisibleSpatialSideEffect(execution)
                await actions.dismissImmersiveSpace()
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
        execution: Execution,
        allowsPendingSessionStart: Bool = false
    ) async -> Bool? {
        guard executionIsLive(execution) else { return nil }
        let settled = await playbackRuntime.waitUntilPresentationSettled(
            to: presentation,
            allowsPendingSessionStart: allowsPendingSessionStart
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

    /// A playing transfer must advance the replacement renderer before
    /// RealityKit can confirm a first displayed pixel in every presentation.
    /// Paused transfers have no after-success intent and remain paused.
    private func restoreTargetPlaybackIntentBeforeSettlement(
        _ execution: Execution
    ) async -> Bool {
        guard let intent = execution.request.playbackTransportPlan?.afterSuccess else {
            return true
        }
        while playbackRuntime.productLifecycle == .loading {
            guard executionIsLive(execution) else { return false }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        guard executionIsLive(execution) else { return false }
        if case .resume(let mediaSessionID) = intent {
            do {
                try await playbackRuntime.beginPlaybackForPresentationSettlement(
                    mediaSessionID: mediaSessionID
                )
                guard executionIsLive(execution) else { return false }
                lastExecutionCheckpoint = "target-playback-intent-restored"
                return true
            } catch {
                guard setRuntimeError(
                    error.localizedDescription,
                    execution: execution
                ) else {
                    return false
                }
                _ = await complete(
                    execution,
                    outcome: .failed(.playbackPauseFailed),
                    performsAfterTransport: false
                )
                return false
            }
        }
        switch await executePlaybackTransport(intent, execution: execution) {
        case .succeeded:
            lastExecutionCheckpoint = "target-playback-intent-restored"
            return true
        case .invalidated:
            return false
        case .failed(_, let message):
            guard setRuntimeError(message, execution: execution) else {
                return false
            }
            _ = await complete(
                execution,
                outcome: .failed(.playbackPauseFailed),
                performsAfterTransport: false
            )
            return false
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
        if case .failed = outcome {
            let diagnostic = [
                "outcome=\(String(describing: outcome))",
                "operation=\(lastPlatformOperation)",
                "checkpoint=\(lastExecutionCheckpoint)",
                "lifecycle=\(playbackRuntime.productLifecycle.rawValue)",
                "runtime=\(playbackRuntime.lastErrorMessage ?? "none")"
            ].joined(separator: ",")
            appModel.recordPresentationConversionDiagnostic(diagnostic)
            logger.error(
                "Playback presentation conversion failed \(diagnostic, privacy: .public)"
            )
            switch execution.request.effect {
            case .presentInitialSpatialPlayback,
                 .presentSpatialPlayback,
                 .presentWindowPlayback,
                 .switchWindowHostedPlayback:
                appModel.deferPresentationConversionFailureUntilMediaLibraryIsVisible(
                    "无法切换播放显示方式，已返回媒体资料库。"
                )
                await stopPlaybackForFailedPresentationTransfer()
                appModel.requestStoppedPlaybackCleanup()
                lastExecutionResolution =
                    "\(String(describing: outcome))-playback-stopped"
                lastExecutionCheckpoint = "presentation-conversion-failed"
                return .ignored
            default:
                break
            }
        }
        let presentationRestoredAfterFailure: PlaybackPresentation? = switch outcome {
        case .succeeded:
            nil
        case .failed:
            switch execution.request.effect {
            case .presentInitialSpatialPlayback,
                 .presentSpatialPlayback,
                 .presentWindowPlayback,
                 .switchWindowHostedPlayback:
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
