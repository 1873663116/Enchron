import AVFoundation
import Foundation
import CoreGraphics
import CoreVideo
import Observation
import OSLog
import PlaybackFeature
import PlaybackPresentation
import SwiftUI
import UIKit
import VideoToolbox

#if os(visionOS)
enum SpatialPlatformImmersiveSpaceReconciliationPolicy {
    static func shouldRecordDisappearance(
        immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency,
        presentation: PlaybackPresentation,
        transitionIsActive: Bool,
        hasPendingSpatialPlatformEffect: Bool,
        hasConnectedImmersiveSpaceScene: Bool
    ) -> Bool {
        immersiveSpaceResidency == .open
            && presentation.usesImmersiveSpace
            && transitionIsActive == false
            && hasPendingSpatialPlatformEffect == false
            && hasConnectedImmersiveSpaceScene == false
    }
}

enum SpatialPlatformImmersiveExitWindowRevealPolicy {
    static func shouldRevealMainWindow(
        sourceRendererIsReleased: Bool,
        targetSessionIsActivated: Bool
    ) -> Bool {
        sourceRendererIsReleased && targetSessionIsActivated
    }

    static func shouldBeginVisualCutover(
        transition: PlaybackPresentationTransition?,
        surfacePresentation: PlaybackPresentation,
        targetSurfacePixelIdentityIsCurrent: Bool
    ) -> Bool {
        guard let transition,
              transition.previousPresentation.usesImmersiveSpace,
              transition.targetPresentation.usesMainWindow,
              transition.targetPresentation == surfacePresentation else {
            return false
        }
        return targetSurfacePixelIdentityIsCurrent
    }

    static func shouldShowLastFrameBridge(
        family: PresentationContentFamily,
        targetIsSettled: Bool,
        hasCapturedFrame: Bool
    ) -> Bool {
        family == .panoramic && targetIsSettled == false && hasCapturedFrame
    }
}

@MainActor
@Observable
final class SpatialPlatformEffectCoordinator {
    fileprivate struct SceneActions {
        let windowIdentity: SpatialPlatformWindowIdentity?
        let openImmersiveSpace: OpenImmersiveSpaceAction
        let dismissImmersiveSpace: DismissImmersiveSpaceAction
        let openWindow: OpenWindowAction
        let dismissWindow: DismissWindowAction
        let pushWindow: PushWindowAction
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

    private enum ImmersivePlaybackExitMode {
        case appRequested(keepsEnvironmentOpen: Bool)
        case alreadyClosedBySystem

        var waitsForSourceFade: Bool {
            switch self {
            case .appRequested:
                true
            case .alreadyClosedBySystem:
                false
            }
        }

        var dismissesImmersiveSpace: Bool {
            switch self {
            case .appRequested(let keepsEnvironmentOpen):
                keepsEnvironmentOpen == false
            case .alreadyClosedBySystem:
                false
            }
        }
    }

    private enum MainWindowRestorationMethod {
        case dismissedResidentWindow
        case openedMainWindow
    }

    private struct MainWindowRestoration {
        let method: MainWindowRestorationMethod
        let isReady: Bool
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
    private let playbackVideoEntityStore: PlaybackVideoEntityStore
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
    private weak var mainWindowScene: UIWindowScene?
    @ObservationIgnored
    private var mainWindowSceneSessionIdentifier: String?
    @ObservationIgnored
    private var windowCapabilityIDs: [SpatialPlatformWindowIdentity: UUID] = [:]
    @ObservationIgnored
    private var residentWindowState = SpatialPlatformResidentWindowState.absent

    private(set) var lastPlatformOperation = "none"
    private(set) var lastExecutionCheckpoint = "none"
    private(set) var executionAttemptCount: UInt64 = 0
    private(set) var lastExecutionResolution = "none"
    private(set) var portalPlaybackViewportRefreshState =
        PortalPlaybackViewportRefreshState()

    var mainWindowPlaybackSurfaceRefreshRevision: UInt64 {
        portalPlaybackViewportRefreshState.requestedRevision
    }

    var mainWindowPlaybackSurfaceAppliedRefreshRevision: UInt64 {
        portalPlaybackViewportRefreshState.appliedRevision
    }

    private static let immersiveSpaceLifecycleConfirmationTimeout =
        Duration.seconds(5)
    private static let windowLifecycleConfirmationTimeout = Duration.seconds(5)
    init(
        appModel: AppModel,
        playbackRuntime: PlaybackRuntime,
        playbackVideoEntityStore: PlaybackVideoEntityStore,
        stopPlaybackForFailedPresentationTransfer: (@MainActor () async -> Void)? = nil,
        persistSettledPlaybackMode: (@MainActor (PlaybackPresentation) -> Void)? = nil
    ) {
        self.appModel = appModel
        self.playbackRuntime = playbackRuntime
        self.playbackVideoEntityStore = playbackVideoEntityStore
        self.stopPlaybackForFailedPresentationTransfer =
            stopPlaybackForFailedPresentationTransfer
            ?? { await playbackRuntime.stopAndWait() }
        self.persistSettledPlaybackMode = persistSettledPlaybackMode ?? { _ in }
        appModel.setSpatialPlatformEffectReplacementHandler { [weak self] in
            self?.requestDrain()
        }
    }

    func recordMainWindowPlaybackSurfaceRefreshApplied(_ revision: UInt64) {
        guard revision > 0,
              revision <= portalPlaybackViewportRefreshState.requestedRevision else {
            return
        }
        portalPlaybackViewportRefreshState.recordApplied(revision)
        appModel.recordSurfaceInputProbe(
            "portalViewportRefresh appliedRevision=\(revision)"
        )
    }

    fileprivate func register(
        id: UUID,
        actions: SceneActions
    ) {
        if let windowIdentity = actions.windowIdentity {
            windowCapabilityIDs[windowIdentity] = id
        }
        let invalidatedLease = leaseRegistry.register(
            actions,
            id: id,
            makePreferred:
                actions.windowIdentity == .immersivePlaybackResident
        )
        if let invalidatedLease {
            invalidateTask(invalidatedLease)
        }
        lastPlatformOperation = "executor-registered"
        requestDrain()
    }

    func unregister(id: UUID) {
        let windowIdentity = windowCapabilityIDs.first {
            $0.value == id
        }?.key
        if let windowIdentity {
            windowCapabilityIDs[windowIdentity] = nil
        }
        let preferredFallbackID = windowIdentity
            == .immersivePlaybackResident
            ? windowCapabilityIDs[.main]
            : nil
        if let invalidatedLease = leaseRegistry.unregister(
            id: id,
            preferredFallbackID: preferredFallbackID
        ) {
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

    func reconcileImmersiveSpaceResidency() {
        let hasConnectedImmersiveSpaceScene =
            UIApplication.shared.connectedScenes.contains { scene in
                scene.session.role == .immersiveSpaceApplication
            }
        reconcileImmersiveSpaceResidency(
            hasConnectedImmersiveSpaceScene: hasConnectedImmersiveSpaceScene
        )
    }

    func reconcileImmersiveSpaceResidency(
        hasConnectedImmersiveSpaceScene: Bool
    ) {
        guard SpatialPlatformImmersiveSpaceReconciliationPolicy
            .shouldRecordDisappearance(
                immersiveSpaceResidency: appModel.immersiveSpaceResidency,
                presentation: appModel.playbackPresentation,
                transitionIsActive: appModel.presentationTransition != nil,
                hasPendingSpatialPlatformEffect:
                    appModel.pendingSpatialPlatformEffect != nil,
                hasConnectedImmersiveSpaceScene: hasConnectedImmersiveSpaceScene
            ) else {
            return
        }

        let playbackContext = playbackRuntime.activeSessionID.map {
            SpatialPlaybackTransitionContext(
                mediaSessionID: $0,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        }
        let attachedPresentation = playbackRuntime.attachedPresentation
        appModel.recordSurfaceInputProbe(
            "immersiveSpaceDisappearanceReconciled"
                + " presentation=\(appModel.playbackPresentation.rawValue)"
                + " attached=\(attachedPresentation?.rawValue ?? "none")"
                + " lifecycle=\(playbackRuntime.productLifecycle.rawValue)"
        )
        if attachedPresentation != .window {
            playbackRuntime.detach()
        }
        recordImmersiveSpaceResidency(.closed)
        _ = appModel.receiveSpatialPlatformResult(
            .immersiveSpaceDisappeared(playbackContext)
        )
        requestDrain()
    }

    func recordWindowResidency(
        _ residency: SpatialPlatformWindowResidency,
        for window: SpatialPlatformWindowIdentity
    ) {
        if window == .immersivePlaybackResident {
            residentWindowState = switch residency {
            case .open:
                .open
            case .closed:
                .absent
            }
        }
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
        if let windowScene {
            mainWindowSceneSessionIdentifier =
                windowScene.session.persistentIdentifier
        }
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
        case .enterImmersivePlayback(let family):
            await enterImmersivePlayback(
                family: family,
                execution: execution
            )
        case .exitImmersivePlayback(let family, let keepsEnvironmentOpen):
            await exitImmersivePlayback(
                family: family,
                mode: .appRequested(
                    keepsEnvironmentOpen: keepsEnvironmentOpen
                ),
                execution: execution
            )
        case .collapseImmersivePlayback(let family):
            await exitImmersivePlayback(
                family: family,
                mode: .alreadyClosedBySystem,
                execution: execution
            )
        case .swapWindowPlaybackProjection(let family):
            await swapWindowPlaybackProjection(to: family, execution: execution)
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
            guard (await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )).isReady else { return }
            if keepsEnvironmentOpen == false {
                guard await dismissImmersiveSpace(execution: execution) else { return }
            }
            _ = await complete(execution, outcome: .succeeded)
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
              (await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
              )).isReady else {
            return
        }
        if keepsEnvironmentOpen == false {
            guard await dismissImmersiveSpace(execution: execution) else {
                return
            }
        }
        _ = await complete(execution, outcome: .succeeded)
    }

    private func enterImmersivePlayback(
        family: PresentationContentFamily,
        execution: Execution
    ) async {
        let presentation = family.immersivePresentation
        guard await yieldExecution(execution) else {
            return
        }
        guard await dismissEnvironmentCardIfNeeded(execution: execution) else {
            return
        }
        let replacementTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime
                .prepareTechnicalSessionForPresentationConversion()
        }
        guard await pushResidentWindowAndWaitForAppearance(
            execution: execution
        ) else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            await recoverFromFailedResidentWindowPush(execution: execution)
            guard setRuntimeError(
                "The resident playback Window could not become usable.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.mainWindowUnavailable)
            )
            return
        }
        guard let openDisposition = await openImmersiveSpaceIfNeeded(
            execution: execution
        ) else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
        }
        guard openDisposition != .unavailable else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            _ = await complete(
                execution,
                outcome: .failed(.immersiveSpaceUnavailable)
            )
            return
        }
        do {
            try await replacementTask.value
        } catch {
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The \(presentation.rawValue.capitalized) RealityView could not assemble its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else {
                return
            }
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }

        guard appModel.allowPresentationSourceRendererRelease() else {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            return
        }
        do {
            try await playbackRuntime.activatePreparedTechnicalSessionReplacement()
        } catch {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The \(presentation.rawValue.capitalized) RealityView could not activate its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else { return }
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }
        guard appModel.allowPresentationTargetRendererBinding() else {
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            return
        }
        do {
            try await playbackRuntime.rebaseActivatedTechnicalSessionReplacement(
                to: presentation
            )
        } catch {
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The \(presentation.rawValue.capitalized) RealityView could not rebase its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else { return }
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }

        guard await restoreTargetPlaybackIntentBeforeSettlement(
            execution,
            restoresMainWindowOnFailure: true
        ) else {
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
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }
        lastPlatformOperation = "spatial-surface-settled"

        guard appModel.beginPresentationVisualCutover() else {
            _ = await restoreMainWindow(
                for: .normalizeSpatialPlayback,
                execution: execution
            )
            return
        }
        appModel.finishPresentationVisualCutover()
        await releaseDepartingPresentationResources()
        let resolution = await complete(execution, outcome: .succeeded)
        guard resolution == .presentationCommitted(presentation) else {
            return
        }
        persistSettledPlaybackMode(presentation)
    }

    private func exitImmersivePlayback(
        family: PresentationContentFamily,
        mode: ImmersivePlaybackExitMode,
        execution: Execution
    ) async {
        let presentation = family.mainWindowPresentation
        lastPlatformOperation = "window-return-started"
        let replacementTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime
                .prepareTechnicalSessionForPresentationConversion()
        }
        let windowTransition: SpatialPlatformPlaybackWindowTransition =
            switch mode {
            case .appRequested:
                .exitImmersivePlayback(family)
            case .alreadyClosedBySystem:
                .collapseImmersivePlayback(family)
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

        let lastFrameBridge = family == .panoramic
            ? portalExitLastFrameBridge()
            : nil
        appModel.setPortalExitLastFrame(lastFrameBridge)
        defer { appModel.setPortalExitLastFrame(nil) }

        guard executionIsLive(execution),
              appModel.allowPresentationSourceRendererRelease(),
              detachPlaybackSurface(execution: execution) else {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
        }

        if family != .panoramic, mode.waitsForSourceFade {
            guard await waitUntilPresentationTransitionTime(
                PlaybackPresentationTransitionAppearance.sourceFadeDuration,
                execution: execution
            ) else {
                await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
                return
            }
        }
        guard let rendererReleased = await waitUntilRendererConsumerIsReleased(
            from: appModel.presentationTransition?.previousPresentation,
            execution: execution
        ) else {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
        }
        guard rendererReleased else {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            lastPlatformOperation = "renderer-release-failed"
            guard setRuntimeError(
                "The spatial playback surface could not release the video renderer.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.rendererReleaseUnavailable)
            )
            return
        }

        if mode.dismissesImmersiveSpace,
           await dismissImmersiveSpace(execution: execution) == false {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            lastPlatformOperation = "immersive-space-dismiss-failed"
            return
        }

        lastPlatformOperation = "main-window-requested"
        do {
            try await playbackRuntime.activatePreparedTechnicalSessionReplacement()
        } catch {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            _ = await restoreMainWindow(
                for: windowTransition,
                execution: execution
            )
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The Window could not activate its replacement playback session: \(error.localizedDescription)",
                    execution: execution
                  ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }
        guard appModel.allowPresentationTargetRendererBinding() else {
            return
        }
        guard SpatialPlatformImmersiveExitWindowRevealPolicy.shouldRevealMainWindow(
            sourceRendererIsReleased: rendererReleased,
            targetSessionIsActivated: true
        ) else {
            return
        }
        recordMainWindowRevealGate(
            immersiveSpaceWasDismissed: mode.dismissesImmersiveSpace
        )

        let rebaseTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime.rebaseActivatedTechnicalSessionReplacement(
                to: presentation
            )
        }
        let restoration = await restoreMainWindow(
            for: windowTransition,
            execution: execution
        )
        guard restoration.isReady else {
            rebaseTask.cancel()
            _ = try? await rebaseTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            lastPlatformOperation = "main-window-appearance-failed"
            guard executionIsLive(execution) else { return }
            if case .openedMainWindow = restoration.method {
                _ = dismissWindow(id: "main", execution: execution)
            }
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
            try await rebaseTask.value
        } catch {
            guard executionIsLive(execution),
                  setRuntimeError(
                    "The Window could not rebase its replacement playback session: \(error.localizedDescription)",
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
            if case .openedMainWindow = restoration.method {
                guard dismissWindow(id: "main", execution: execution) else {
                    return
                }
            }
            guard setRuntimeError(
                "The window playback surface could not become ready.",
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }
        // The target surface normally starts the cutover itself the moment it
        // proves its pixels carry the current identity, which is what makes the
        // exit fast. Settlement here is the same proof arriving one round trip
        // later, so when the surface did not get the chance — no further
        // RealityView update, or the transition changed underneath it — this
        // starts the cutover instead of leaving the transition uncommitted.
        if appModel.presentationVisualCutoverMayBegin == false {
            guard appModel.beginPresentationVisualCutover() else { return }
            appModel.recordSurfaceInputProbe(
                "portalVisualCutover source=settlementFallback animated=false"
            )
        }
        if PortalPlaybackViewportRefreshPolicy.requiresRefresh(
            for: windowTransition
        ) {
            let refreshRevision = portalPlaybackViewportRefreshState.request()
            lastPlatformOperation = "portal-viewport-refresh-requested"
            guard await waitUntilPortalPlaybackViewportRefreshApplied(
                refreshRevision,
                execution: execution
            ) else {
                guard executionIsLive(execution),
                      setRuntimeError(
                        "The Portal viewport could not apply its foreground refresh.",
                        execution: execution
                      ) else { return }
                _ = await complete(
                    execution,
                    outcome: .failed(.windowPlaybackSurfaceUnavailable)
                )
                return
            }
        }
        guard await orderWindowToFront(.main, execution: execution) else {
            lastPlatformOperation = "main-window-activation-failed"
            return
        }
        await releaseDepartingPresentationResources()
        let resolution = await complete(execution, outcome: .succeeded)
        if case .presentationCommitted(let committedPresentation) = resolution {
            persistSettledPlaybackMode(committedPresentation)
        }
        if case .presentationCommitted(.window) = resolution {
            lastPlatformOperation = "window-return-completed"
        }
    }

    private func swapWindowPlaybackProjection(
        to family: PresentationContentFamily,
        execution: Execution
    ) async {
        let presentation = family.mainWindowPresentation
        do {
            try await playbackRuntime.prepareTechnicalSessionForPresentationConversion()
            try await playbackRuntime.activatePreparedTechnicalSessionReplacement()
            try await playbackRuntime.rebaseActivatedTechnicalSessionReplacement(
                to: presentation
            )
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
        await releaseDepartingPresentationResources()
        let resolution = await complete(execution, outcome: .succeeded)
        if case .presentationCommitted(let committedPresentation) = resolution {
            persistSettledPlaybackMode(committedPresentation)
        }
    }

    private func releaseDepartingPresentationResources() async {
        playbackVideoEntityStore.releaseDepartingEntity()
        await playbackRuntime.retireDepartingTechnicalSessionAfterSceneDisappearance()
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

    private func pushResidentWindowAndWaitForAppearance(
        execution: Execution
    ) async -> Bool {
        let residentWindow = SpatialPlatformWindowIdentity
            .immersivePlaybackResident
        let observationRevision = windowObservation.revision(
            for: residentWindow
        )
        guard executionIsLive(execution),
              let actions = leaseRegistry.currentCapability,
              actions.windowIdentity == .main else {
            return false
        }
        residentWindowState = .opening
        markVisibleSpatialSideEffect(execution)
        lastPlatformOperation = "immersivePlaybackResident-window-pushed"
        actions.pushWindow(id: residentWindow.rawValue)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            if windowObservation.confirms(
                .open,
                for: residentWindow,
                after: observationRevision
            ), leaseRegistry.currentCapability?.windowIdentity
                == residentWindow {
                lastPlatformOperation =
                    "immersivePlaybackResident-window-appeared"
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        logger.error("Resident playback Window lifecycle confirmation timed out")
        return false
    }

    private func restoreMainWindow(
        for transition: SpatialPlatformPlaybackWindowTransition,
        execution: Execution
    ) async -> MainWindowRestoration {
        let action = SpatialPlatformPlaybackWindowPolicy.action(
            for: transition,
            residentWindowState: residentWindowState
        )
        switch action {
        case .pushResidentWindow:
            return MainWindowRestoration(
                method: .openedMainWindow,
                isReady: false
            )
        case .dismissResidentWindow:
            if await dismissWindowAndWaitForDisappearance(
                .immersivePlaybackResident,
                execution: execution
            ), await waitForMainWindowToBecomeForeground(
                execution: execution
            ) {
                preferMainWindowCapability()
                return MainWindowRestoration(
                    method: .dismissedResidentWindow,
                    isReady: true
                )
            }
            guard executionIsLive(execution) else {
                return MainWindowRestoration(
                    method: .dismissedResidentWindow,
                    isReady: false
                )
            }
            let isReady = await openWindowAndWaitForAppearance(
                .main,
                execution: execution
            )
            if isReady {
                preferMainWindowCapability()
            }
            return MainWindowRestoration(
                method: .openedMainWindow,
                isReady: isReady
            )
        case .openMainWindow:
            let isReady = await openWindowAndWaitForAppearance(
                .main,
                execution: execution
            )
            if isReady {
                preferMainWindowCapability()
            }
            return MainWindowRestoration(
                method: .openedMainWindow,
                isReady: isReady
            )
        }
    }

    private func recoverFromFailedResidentWindowPush(
        execution: Execution
    ) async {
        guard executionIsLive(execution) else { return }
        _ = await restoreMainWindow(
            for: .normalizeSpatialPlayback,
            execution: execution
        )
    }

    private func waitForMainWindowToBecomeForeground(
        execution: Execution
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            let observedMainWindowScene = mainWindowScene
                ?? UIApplication.shared.connectedScenes.first { scene in
                    scene.session.persistentIdentifier
                        == mainWindowSceneSessionIdentifier
                } as? UIWindowScene
            if observedMainWindowScene?.activationState == .foregroundActive {
                lastPlatformOperation = "main-window-restored"
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        logger.error("Retained Main Window foreground confirmation timed out")
        return false
    }

    private func waitUntilPortalPlaybackViewportRefreshApplied(
        _ revision: UInt64,
        execution: Execution
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            if portalPlaybackViewportRefreshState.hasApplied(revision) {
                lastPlatformOperation = "portal-viewport-refresh-applied"
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        logger.error(
            "Portal viewport refresh confirmation timed out revision=\(revision)"
        )
        return false
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
        appModel.recordSurfaceInputProbe(
            "windowConfirmTimeout window=\(window.rawValue)"
                + " observed=\(String(describing: windowObservation.residency(for: window)))"
                + " baselineRevision=\(observationRevision)"
                + " currentRevision=\(windowObservation.revision(for: window))"
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
        case SpatialPlatformWindowIdentity.immersivePlaybackResident.rawValue:
            residentWindowState = .closing
            actions.dismissWindow(id: id)
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
        var residentAppearanceRevisionDismissed = observationRevision
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
            if window == .immersivePlaybackResident,
               windowObservation.residency(for: window) == .open,
               windowObservation.revision(for: window)
                > residentAppearanceRevisionDismissed {
                residentAppearanceRevisionDismissed =
                    windowObservation.revision(for: window)
                guard dismissWindow(
                    id: window.rawValue,
                    execution: execution
                ) else {
                    return false
                }
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

    private func preferMainWindowCapability() {
        guard let capabilityID = windowCapabilityIDs[.main] else { return }
        _ = leaseRegistry.preferCapability(id: capabilityID)
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
        case .enterImmersivePlayback(let family):
            .playback(family.immersivePresentation)
        case .exitImmersivePlayback,
             .collapseImmersivePlayback,
             .swapWindowPlaybackProjection,
             .dismissEnvironmentPreview,
             .presentEnvironmentCard,
             .normalizeStoppedSpatialPlayback,
             .normalizeInvalidatedSpatialPlayback:
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
        appModel.recordSurfaceInputProbe(
            "immersiveConfirmTimeout expected=\(expectedResidency)"
                + " observed=\(observedResidency)"
                + " baselineRevision=\(revision)"
                + " currentRevision=\(immersiveSpaceObservation.revision)"
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

    private func recordMainWindowRevealGate(
        immersiveSpaceWasDismissed: Bool
    ) {
        appModel.recordSurfaceInputProbe(
            "portalWindowRevealGate"
                + " sourceRendererReleased=true"
                + " targetSessionActivated=true"
                + " immersiveSpaceDismissed=\(immersiveSpaceWasDismissed)"
        )
    }

    private func portalExitLastFrameBridge() -> CGImage? {
        guard let pixelBuffer = playbackRuntime.renderer?.displayedPixelBuffer()
        else {
            appModel.recordSurfaceInputProbe(
                "portalLastFrameBridge captured=false reason=noDisplayedPixel"
            )
            return nil
        }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(
            pixelBuffer,
            options: nil,
            imageOut: &image
        ) == noErr, var image else {
            appModel.recordSurfaceInputProbe(
                "portalLastFrameBridge captured=false reason=conversionFailed"
            )
            return nil
        }
        switch playbackRuntime.effectiveStereoLayout {
        case .topBottom:
            image = image.cropping(
                to: CGRect(
                    x: 0,
                    y: CGFloat(image.height) / 2,
                    width: CGFloat(image.width),
                    height: CGFloat(image.height) / 2
                )
            ) ?? image
        case .sideBySide:
            image = image.cropping(
                to: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(image.width) / 2,
                    height: CGFloat(image.height)
                )
            ) ?? image
        case .mono, .multiview:
            break
        }
        appModel.recordSurfaceInputProbe(
            "portalLastFrameBridge captured=true width=\(image.width)"
                + " height=\(image.height)"
                + " stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)"
        )
        return image
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
        _ execution: Execution,
        restoresMainWindowOnFailure: Bool = false
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
                if restoresMainWindowOnFailure {
                    _ = await restoreMainWindow(
                        for: .normalizeSpatialPlayback,
                        execution: execution
                    )
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
            if restoresMainWindowOnFailure {
                _ = await restoreMainWindow(
                    for: .normalizeSpatialPlayback,
                    execution: execution
                )
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
            case .enterImmersivePlayback,
                 .exitImmersivePlayback,
                 .collapseImmersivePlayback,
                 .swapWindowPlaybackProjection:
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
            case .enterImmersivePlayback,
                 .exitImmersivePlayback,
                 .collapseImmersivePlayback,
                 .swapWindowPlaybackProjection:
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
    @Environment(\.pushWindow) private var pushWindow
    @State private var registrationID = UUID()
    private let windowIdentity: SpatialPlatformWindowIdentity?

    init(windowIdentity: SpatialPlatformWindowIdentity? = nil) {
        self.windowIdentity = windowIdentity
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                coordinator.register(
                    id: registrationID,
                    actions: .init(
                        windowIdentity: windowIdentity,
                        openImmersiveSpace: openImmersiveSpace,
                        dismissImmersiveSpace: dismissImmersiveSpace,
                        openWindow: openWindow,
                        dismissWindow: dismissWindow,
                        pushWindow: pushWindow
                    )
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
