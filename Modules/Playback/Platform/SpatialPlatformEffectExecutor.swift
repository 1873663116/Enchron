import AVFoundation
import Foundation
import CoreGraphics
import CoreVideo
import Observation
import OSLog
import SwiftUI
import UIKit

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

enum SpatialPlatformPresentationFailureRecovery: Equatable, Sendable {
    case unavailable
    case previousPresentationRestored
}

enum SpatialPlatformPresentationFailurePolicy {
    static func shouldStopPlayback(
        effect: SpatialPlatformEffect,
        recovery: SpatialPlatformPresentationFailureRecovery
    ) -> Bool {
        guard recovery != .previousPresentationRestored else { return false }
        switch effect {
        case .enterImmersivePlayback,
             .exitImmersivePlayback,
             .collapseImmersivePlayback,
             .swapWindowPlaybackProjection:
            return true
        case .presentEnvironmentPreview,
             .dismissEnvironmentPreview,
             .presentEnvironmentCard,
             .normalizeStoppedSpatialPlayback,
             .normalizeInvalidatedSpatialPlayback:
            return false
        }
    }
}

enum SpatialPlatformPlayerWindowClosurePolicy {
    static func stopsPlayback(
        hasActivePlaybackRequest: Bool,
        playerWindowStateBeforeDisconnect: SpatialPlatformPlayerWindowState
    ) -> Bool {
        hasActivePlaybackRequest && playerWindowStateBeforeDisconnect != .closing
    }
}

public enum SpatialPlatformPlayerWindowDestructionPolicy {
    public static let conditions: Set<UIScene.DestructionCondition> =
        [.userInitiatedDismissal]
}

public enum SpatialPlatformWindowScenePolicy {
    public static func isOrphaned(
        ownSessionIdentifier: String?,
        liveSessionIdentifier: String?
    ) -> Bool {
        guard let ownSessionIdentifier, let liveSessionIdentifier else { return false }
        return ownSessionIdentifier != liveSessionIdentifier
    }
}

public enum SpatialPlatformImmersiveExitWindowRevealPolicy {
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

    public static func isRevealingMainWindow(
        transition: PlaybackPresentationTransition?
    ) -> Bool {
        guard let transition else { return false }
        return transition.previousPresentation.usesImmersiveSpace
            && transition.targetPresentation.usesMainWindow
    }
}

@MainActor
@Observable
public final class SpatialPlatformEffectCoordinator {
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

        var dismissesImmersiveSpace: Bool {
            switch self {
            case .appRequested(let keepsEnvironmentOpen):
                keepsEnvironmentOpen == false
            case .alreadyClosedBySystem:
                false
            }
        }
    }

    private enum ExecutionPhase {
        case currentRequest
        case settledRequest
    }

    private enum GuardedTransportResult {
        case succeeded
        case invalidated
        case failed(reason: SpatialPlaybackTransportFailureReason)
    }

    private let appModel: PlaybackSessionModel
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
    private weak var playerWindowScene: UIWindowScene?
    @ObservationIgnored
    private var windowSceneSessionIdentifiers:
        [SpatialPlatformWindowIdentity: String] = [:]
    public private(set) var liveWindowSessionIdentifiers:
        [SpatialPlatformWindowIdentity: String] = [:]
    @ObservationIgnored
    private var sceneDisconnectObserver: (any NSObjectProtocol)?
    @ObservationIgnored
    public var onPlayerWindowClosedByWearer: (@MainActor () -> Void)?
    @ObservationIgnored
    private var windowCapabilityIDs: [SpatialPlatformWindowIdentity: UUID] = [:]
    @ObservationIgnored
    private var playerWindowState = SpatialPlatformPlayerWindowState.absent

    public private(set) var lastPlatformOperation = "none"
    public private(set) var lastExecutionCheckpoint = "none"
    public private(set) var executionAttemptCount: UInt64 = 0
    public private(set) var lastExecutionResolution = "none"
    private(set) var portalPlaybackViewportRefreshState =
        PortalPlaybackViewportRefreshState()

    public var mainWindowPlaybackSurfaceRefreshRevision: UInt64 {
        portalPlaybackViewportRefreshState.requestedRevision
    }

    public var mainWindowPlaybackSurfaceAppliedRefreshRevision: UInt64 {
        portalPlaybackViewportRefreshState.appliedRevision
    }

    private static let immersiveSpaceLifecycleConfirmationTimeout =
        Duration.seconds(5)
    private static let windowLifecycleConfirmationTimeout = Duration.seconds(5)
    public init(
        session: PlaybackSessionModel,
        playbackRuntime: PlaybackRuntime,
        playbackVideoEntityStore: PlaybackVideoEntityStore,
        stopPlaybackForFailedPresentationTransfer: @escaping @MainActor () async -> Void,
        persistSettledPlaybackMode: (@MainActor (PlaybackPresentation) -> Void)? = nil
    ) {
        self.appModel = session
        self.playbackRuntime = playbackRuntime
        self.playbackVideoEntityStore = playbackVideoEntityStore
        self.stopPlaybackForFailedPresentationTransfer =
            stopPlaybackForFailedPresentationTransfer
        self.persistSettledPlaybackMode = persistSettledPlaybackMode ?? { _ in }
        appModel.setSpatialPlatformEffectReplacementHandler { [weak self] in
            self?.requestDrain()
        }
        observeSceneDisconnections()
    }

    private func observeSceneDisconnections() {
        sceneDisconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            nonisolated(unsafe) let object = notification.object
            let identifier = MainActor.assumeIsolated {
                (object as? UIScene)?.session.persistentIdentifier
            }
            Task { @MainActor [weak self] in
                self?.windowSceneDidDisconnect(sessionIdentifier: identifier)
            }
        }
    }

    private func windowSceneDidDisconnect(sessionIdentifier: String?) {
        guard let sessionIdentifier,
              let window = windowSceneSessionIdentifiers.first(where: {
                  $0.value == sessionIdentifier
              })?.key else {
            return
        }
        windowSceneSessionIdentifiers[window] = nil
        liveWindowSessionIdentifiers[window] = nil
        switch window {
        case .main:
            mainWindowScene = nil
        case .player:
            playerWindowScene = nil
        }
        let playerWindowStateBeforeDisconnect = playerWindowState
        recordWindowResidency(.closed, for: window)
        guard window == .player else { return }
        let stopsPlayback = SpatialPlatformPlayerWindowClosurePolicy.stopsPlayback(
            hasActivePlaybackRequest: playbackRuntime.hasActivePlaybackRequest,
            playerWindowStateBeforeDisconnect: playerWindowStateBeforeDisconnect
        )
        appModel.recordSurfaceInputProbe(
            "playerWindowScene disconnected stopsPlayback=\(stopsPlayback)",
            retention: .evidence
        )
        guard stopsPlayback else { return }
        onPlayerWindowClosedByWearer?()
    }

    public func recordMainWindowPlaybackSurfaceRefreshApplied(_ revision: UInt64) {
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
            makePreferred: actions.windowIdentity != nil
                && actions.windowIdentity != .main
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
        let preferredFallbackID: UUID? = switch windowIdentity {
        case .player:
            windowCapabilityIDs[.player] ?? windowCapabilityIDs[.main]
        case .main, nil:
            nil
        }
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

    var playerWindowObservedResidency: String {
        windowObservation.residency(for: .player).map(String.init(describing:))
            ?? "unobserved"
    }

    var playerWindowObservationRevision: UInt64 {
        windowObservation.revision(for: .player)
    }

    public func recordImmersiveSpaceResidency(
        _ residency: SpatialPlatformImmersiveSpaceResidency
    ) {
        immersiveSpaceObservation.record(residency)
        playbackRuntime.recordPlaybackHost(
            residency == .open ? .immersiveSpace : .window
        )
        let residencyDescription = String(describing: residency)
        logger.info(
            """
            Immersive Space lifecycle observed \
            residency=\(residencyDescription, privacy: .public) \
            revision=\(self.immersiveSpaceObservation.revision, privacy: .public)
            """
        )
    }

    public func reconcileImmersiveSpaceResidency() {
        let hasConnectedImmersiveSpaceScene =
            UIApplication.shared.connectedScenes.contains { scene in
                scene.session.role == .immersiveSpaceApplication
            }
        reconcileImmersiveSpaceResidency(
            hasConnectedImmersiveSpaceScene: hasConnectedImmersiveSpaceScene
        )
    }

    public func reconcileImmersiveSpaceResidency(
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

    public func recordWindowResidency(
        _ residency: SpatialPlatformWindowResidency,
        for window: SpatialPlatformWindowIdentity
    ) {
        let observedState: SpatialPlatformPlayerWindowState = switch residency {
        case .open:
            .open
        case .closed:
            .absent
        }
        switch window {
        case .player:
            playerWindowState = observedState
        case .main:
            break
        }
        windowObservation.record(residency, for: window)
        appModel.recordSurfaceInputProbe(
            "windowResidency window=\(window.rawValue)"
                + " residency=\(residency)"
                + " revision=\(windowObservation.revision(for: window))",
            retention: .evidence
        )
    }

    public func recordWindowScene(
        _ windowScene: UIWindowScene?,
        for window: SpatialPlatformWindowIdentity
    ) {
        guard let windowScene else { return }
        guard UIApplication.shared.connectedScenes.contains(windowScene) else {
            appModel.recordSurfaceInputProbe(
                "windowScene reportIgnored window=\(window.rawValue)"
                    + " reason=disconnected"
                    + " session=\(windowScene.session.persistentIdentifier)",
                retention: .evidence
            )
            return
        }
        windowSceneSessionIdentifiers[window] = windowScene.session.persistentIdentifier
        liveWindowSessionIdentifiers[window] = windowScene.session.persistentIdentifier
        switch window {
        case .main:
            mainWindowScene = windowScene
        case .player:
            playerWindowScene = windowScene
            applyPlayerWindowDestructionConditions()
        }
    }

    private func applyPlayerWindowDestructionConditions() {
        guard let playerWindowScene else { return }
        let conditions = SpatialPlatformPlayerWindowDestructionPolicy.conditions
        guard playerWindowScene.destructionConditions != conditions else { return }
        playerWindowScene.destructionConditions = conditions
        appModel.recordSurfaceInputProbe(
            "playerWindowDestruction userInitiatedDismissal="
                + "\(conditions.contains(.userInitiatedDismissal))",
            retention: .evidence
        )
    }

    private func windowSceneHasDisconnected(
        _ window: SpatialPlatformWindowIdentity
    ) -> Bool {
        guard let identifier = windowSceneSessionIdentifiers[window] else {
            return false
        }
        return UIApplication.shared.connectedScenes.contains { scene in
            scene.session.persistentIdentifier == identifier
        } == false
    }

    private func connectedWindowScene(
        _ window: SpatialPlatformWindowIdentity
    ) -> UIWindowScene? {
        if window == .main, let mainWindowScene { return mainWindowScene }
        if window == .player, let playerWindowScene { return playerWindowScene }
        guard let identifier = windowSceneSessionIdentifiers[window] else {
            return nil
        }
        return UIApplication.shared.connectedScenes.first { scene in
            scene.session.persistentIdentifier == identifier
        } as? UIWindowScene
    }

    public func playbackSessionLifecycleChanged(
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
        let pendingRequestBeforeFinish = appModel.pendingSpatialPlatformEffect?.id
        let nextRequestIsReady = SpatialPlatformExecutionDrainPolicy
            .shouldDrainAfterFinish(
                executedRequestID: lease.requestID,
                pendingRequestID: pendingRequestBeforeFinish
            )
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
        if nextRequestIsReady {
            requestDrain()
        }
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
            case .invalidated:
                return
            case .failed(let reason):
                guard setRuntimeIssue(.playbackControlFailed, execution: execution) else { return }
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
                id: PlaybackSessionModel.senseZoneVolumeID,
                execution: execution
            ) else { return }
            _ = await complete(execution, outcome: .succeeded)
        case .normalizeStoppedSpatialPlayback(let keepsEnvironmentOpen):
            guard await restorePlaybackWindow(
                for: normalizeWindowTransition,
                execution: execution
            ) else { return }
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
              await restorePlaybackWindow(
                for: normalizeWindowTransition,
                execution: execution
              ) else {
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
        var openDisposition = ImmersiveOpenDisposition.unavailable
        let handedOver = await performWindowTransition(
            .enterImmersivePlayback(family),
            execution: execution,
            openImmersiveSpace: { [weak self] in
                guard let self,
                      let disposition = await openImmersiveSpaceIfNeeded(
                        execution: execution
                      ) else { return false }
                openDisposition = disposition
                return disposition != .unavailable
            }
        )
        guard handedOver else {
            replacementTask.cancel()
            _ = try? await replacementTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            guard executionIsLive(execution) else { return }
            await recoverFromFailedImmersivePlaybackEntry(execution: execution)
            guard setRuntimeIssue(
                .presentationConversionFailed,
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(
                    openDisposition == .unavailable
                        ? .immersiveSpaceUnavailable
                        : .mainWindowUnavailable
                )
            )
            return
        }
        do {
            try await replacementTask.value
        } catch {
            guard executionIsLive(execution),
                  setRuntimeIssue(
                    .presentationConversionFailed,
                    execution: execution
                  ) else {
                return
            }
            _ = await restorePlaybackWindow(
                for: normalizeWindowTransition,
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
            _ = await restorePlaybackWindow(
                for: normalizeWindowTransition,
                execution: execution
            )
            return
        }
        do {
            try await playbackRuntime.activatePreparedTechnicalSessionReplacement()
        } catch {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            guard executionIsLive(execution),
                  setRuntimeIssue(
                    .presentationConversionFailed,
                    execution: execution
                  ) else { return }
            _ = await restorePlaybackWindow(
                for: normalizeWindowTransition,
                execution: execution
            )
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable)
            )
            return
        }
        guard appModel.allowPresentationTargetRendererBinding() else {
            _ = await restorePlaybackWindow(
                for: normalizeWindowTransition,
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
                  setRuntimeIssue(
                    .presentationConversionFailed,
                    execution: execution
                  ) else { return }
            _ = await restorePlaybackWindow(
                for: normalizeWindowTransition,
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
            restoresPlayerWindowOnFailure: true
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
            guard setRuntimeIssue(
                .surfaceAttachmentFailed,
                execution: execution
            ) else { return }
            let playerWindowIsReady = await restorePlaybackWindow(
                for: normalizeWindowTransition,
                execution: execution
            )
            lastPlatformOperation = "spatial-surface-settlement-failed"
            _ = await complete(
                execution,
                outcome: .failed(.spatialPlaybackSurfaceUnavailable),
                failureRecovery: playerWindowIsReady
                    ? .previousPresentationRestored
                    : .unavailable
            )
            return
        }
        lastPlatformOperation = "spatial-surface-settled"

        guard appModel.beginPresentationVisualCutover() else {
            _ = await restorePlaybackWindow(
                for: normalizeWindowTransition,
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
        let windowTransition = SpatialPlatformPlaybackWindowPolicy.windowTransition(
            for: execution.request.effect,
            residency: playbackRuntime.residency
        ) ?? .exitImmersivePlayback(family)
        do {
            try await replacementTask.value
        } catch {
            guard executionIsLive(execution),
                  setRuntimeIssue(
                    .presentationConversionFailed,
                    execution: execution
                  ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }

        guard executionIsLive(execution),
              appModel.allowPresentationSourceRendererRelease(),
              detachPlaybackSurface(execution: execution) else {
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            return
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
            guard setRuntimeIssue(
                .presentationConversionFailed,
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
            _ = await restorePlaybackWindow(
                for: windowTransition,
                execution: execution
            )
            guard executionIsLive(execution),
                  setRuntimeIssue(
                    .presentationConversionFailed,
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
        recordPlayerWindowRevealGate(
            immersiveSpaceWasDismissed: mode.dismissesImmersiveSpace
        )

        let rebaseTask = Task { @MainActor [playbackRuntime] in
            try await playbackRuntime.rebaseActivatedTechnicalSessionReplacement(
                to: presentation
            )
        }
        let windowRestorationBegan = await performWindowTransition(
            windowTransition,
            execution: execution
        )
        guard windowRestorationBegan else {
            rebaseTask.cancel()
            _ = try? await rebaseTask.value
            await playbackRuntime.cancelPreparedTechnicalSessionReplacement()
            lastPlatformOperation = "main-window-appearance-failed"
            guard executionIsLive(execution) else { return }
            guard setRuntimeIssue(
                .presentationConversionFailed,
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
                  setRuntimeIssue(
                    .presentationConversionFailed,
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
        let playerWindowIsReady = await waitForPlayerWindowToBecomeForeground(
            execution: execution
        )
        guard playerWindowIsReady else {
            lastPlatformOperation = "main-window-appearance-failed"
            guard executionIsLive(execution) else { return }
            guard setRuntimeIssue(
                .presentationConversionFailed,
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.mainWindowUnavailable)
            )
            return
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
                      setRuntimeIssue(
                        .surfaceAttachmentFailed,
                        execution: execution
                      ) else { return }
                _ = await complete(
                    execution,
                    outcome: .failed(.windowPlaybackSurfaceUnavailable)
                )
                return
            }
        }
        guard let settled = await waitUntilPresentationSettled(
            to: presentation,
            execution: execution
        ) else {
            return
        }
        guard settled else {
            lastPlatformOperation = "window-playback-surface-failed"
            guard setRuntimeIssue(
                .surfaceAttachmentFailed,
                execution: execution
            ) else { return }
            _ = await complete(
                execution,
                outcome: .failed(.windowPlaybackSurfaceUnavailable)
            )
            return
        }
        if appModel.presentationVisualCutoverMayBegin == false {
            guard appModel.beginPresentationVisualCutover() else { return }
            appModel.recordSurfaceInputProbe(
                "portalVisualCutover source=settlementFallback"
            )
        }
        guard await orderWindowToFront(.player, execution: execution) else {
            lastPlatformOperation = "player-window-activation-failed"
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
            guard setRuntimeIssue(
                .presentationConversionFailed,
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

    private func capability(
        for window: SpatialPlatformWindowIdentity
    ) -> SceneActions? {
        guard let capabilityID = windowCapabilityIDs[window] else { return nil }
        return leaseRegistry.capability(id: capabilityID)
    }

    private var normalizeWindowTransition:
        SpatialPlatformPlaybackWindowTransition {
        .normalizeSpatialPlayback(
            returnsToPlayer: SpatialPlatformPlaybackWindowPolicy.pushedWindow(
                for: playbackRuntime.residency
            ) == .player
        )
    }

    private func performWindowTransition(
        _ transition: SpatialPlatformPlaybackWindowTransition,
        execution: Execution,
        openImmersiveSpace: (@MainActor () async -> Bool)? = nil
    ) async -> Bool {
        let actions = SpatialPlatformPlaybackWindowPolicy.actions(
            for: transition,
            playerWindowState: playerWindowState
        )
        for action in actions {
            let performed: Bool = switch action {
            case .openImmersiveSpace:
                await (openImmersiveSpace?() ?? false)
            case .dismissPlayerWindow:
                await dismissWindowAndWaitForDisappearance(
                    .player,
                    execution: execution
                )
            case .pushPlayerWindow:
                await pushWindowAndWaitForAppearance(
                    .player,
                    execution: execution
                )
            }
            guard performed else { return false }
        }
        return true
    }

    public func applyPlaybackResidency(_ residency: PlaybackResidency) {
        let transition: SpatialPlatformPlaybackWindowTransition
        switch SpatialPlatformPlaybackWindowPolicy.pushedWindow(for: residency) {
        case .player:
            transition = .startWindowPlayback
        case .none:
            transition = .leaveWindowPlayback
        }
        for action in SpatialPlatformPlaybackWindowPolicy.actions(
            for: transition,
            playerWindowState: playerWindowState
        ) {
            switch action {
            case .pushPlayerWindow:
                issuePushedWindow(.player)
            case .dismissPlayerWindow:
                issueDismissPushedWindow(.player)
            case .openImmersiveSpace:
                break
            }
        }
    }

    @discardableResult
    private func issuePushedWindow(
        _ window: SpatialPlatformWindowIdentity
    ) -> Bool {
        guard let actions = capability(for: .main) else {
            appModel.recordSurfaceInputProbe(
                "pushedWindow push skipped window=\(window.rawValue)"
                    + " cause=noBrowserCapability",
                retention: .evidence
            )
            return false
        }
        switch window {
        case .player:
            playerWindowState = .opening
        case .main:
            return false
        }
        lastPlatformOperation = "\(window.rawValue)-window-pushed"
        actions.pushWindow(id: window.rawValue)
        appModel.recordSurfaceInputProbe(
            "pushedWindow push window=\(window.rawValue)",
            retention: .evidence
        )
        return true
    }

    @discardableResult
    private func issueDismissPushedWindow(
        _ window: SpatialPlatformWindowIdentity
    ) -> Bool {
        guard let actions = capability(for: window) else {
            appModel.recordSurfaceInputProbe(
                "pushedWindow dismiss skipped window=\(window.rawValue)"
                    + " cause=noCapability",
                retention: .evidence
            )
            return false
        }
        switch window {
        case .player:
            playerWindowState = .closing
        case .main:
            return false
        }
        actions.dismissWindow(id: window.rawValue)
        appModel.recordSurfaceInputProbe(
            "pushedWindow dismiss window=\(window.rawValue)",
            retention: .evidence
        )
        return true
    }

    private func pushWindowAndWaitForAppearance(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) async -> Bool {
        let observationRevision = windowObservation.revision(for: window)
        guard executionIsLive(execution) else { return false }
        markVisibleSpatialSideEffect(execution)
        guard issuePushedWindow(window) else { return false }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            if windowObservation.confirms(
                .open,
                for: window,
                after: observationRevision
            ), capability(for: window) != nil {
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
            "Pushed Window lifecycle confirmation timed out window=\(window.rawValue, privacy: .public)"
        )
        return false
    }

    private func restorePlaybackWindow(
        for transition: SpatialPlatformPlaybackWindowTransition,
        execution: Execution
    ) async -> Bool {
        guard await performWindowTransition(
            transition,
            execution: execution
        ) else { return false }
        guard playerWindowState == .opening || playerWindowState == .open else {
            return true
        }
        return await waitForPlayerWindowToBecomeForeground(execution: execution)
    }

    private func recoverFromFailedImmersivePlaybackEntry(
        execution: Execution
    ) async {
        guard executionIsLive(execution) else { return }
        _ = await dismissImmersiveSpace(execution: execution)
        _ = await restorePlaybackWindow(
            for: normalizeWindowTransition,
            execution: execution
        )
    }

    private func waitForPlayerWindowToBecomeForeground(
        execution: Execution
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(
            by: Self.windowLifecycleConfirmationTimeout
        )
        while clock.now < deadline {
            guard executionIsLive(execution) else { return false }
            if connectedWindowScene(.player)?.activationState
                == .foregroundActive {
                if windowObservation.residency(for: .player) != .open {
                    recordWindowResidency(.open, for: .player)
                }
                preferPlayerWindowCapability()
                lastPlatformOperation = "player-window-restored"
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        logger.error("Player Window foreground confirmation timed out")
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
        actions.openWindow(id: id)
        return true
    }

    private func orderWindowToFront(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) async -> Bool {
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
        actions.dismissWindow(id: id)
        return true
    }

    private func dismissPushedWindow(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) -> Bool {
        guard executionIsLive(execution) else { return false }
        markVisibleSpatialSideEffect(execution)
        return issueDismissPushedWindow(window)
    }

    private func dismissWindowAndWaitForDisappearance(
        _ window: SpatialPlatformWindowIdentity,
        execution: Execution
    ) async -> Bool {
        let observationRevision = windowObservation.revision(for: window)
        var appearanceRevisionDismissed = observationRevision
        guard dismissPushedWindow(window, execution: execution) else {
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
            if windowSceneHasDisconnected(window) {
                windowSceneSessionIdentifiers[window] = nil
                recordWindowResidency(.closed, for: window)
                lastPlatformOperation =
                    "\(window.rawValue)-window-scene-disconnected"
                return true
            }
            if windowObservation.residency(for: window) == .open,
               windowObservation.revision(for: window)
                > appearanceRevisionDismissed {
                appearanceRevisionDismissed =
                    windowObservation.revision(for: window)
                guard dismissPushedWindow(window, execution: execution) else {
                    return false
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return false
            }
        }
        appModel.recordSurfaceInputProbe(
            "windowDisappearanceTimeout window=\(window.rawValue)"
                + " residency=\(String(describing: windowObservation.residency(for: window)))"
                + " revision=\(windowObservation.revision(for: window))"
                + " baseline=\(observationRevision)"
                + " connectedWindowScenes=\(UIApplication.shared.connectedScenes.filter { $0.session.role == .windowApplication }.count)",
            retention: .evidence
        )
        return false
    }

    private func preferPlayerWindowCapability() {
        guard let capabilityID = windowCapabilityIDs[.player]
            ?? windowCapabilityIDs[.main] else { return }
        _ = leaseRegistry.preferCapability(id: capabilityID)
    }

    private func dismissEnvironmentCardIfNeeded(
        execution: Execution
    ) async -> Bool {
        guard appModel.environmentCardResidency != .closed else { return true }
        guard dismissWindow(
            id: PlaybackSessionModel.senseZoneVolumeID,
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
            guard setRuntimeIssue(
                .presentationConversionFailed,
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

    private func setRuntimeIssue(
        _ issue: PlaybackUserVisibleIssue,
        execution: Execution,
        phase: ExecutionPhase = .currentRequest
    ) -> Bool {
        guard executionIsLive(execution, phase: phase) else { return false }
        playbackRuntime.setUserVisibleIssue(issue)
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

    private func recordPlayerWindowRevealGate(
        immersiveSpaceWasDismissed: Bool
    ) {
        appModel.recordSurfaceInputProbe(
            "portalWindowRevealGate"
                + " sourceRendererReleased=true"
                + " targetSessionActivated=true"
                + " immersiveSpaceDismissed=\(immersiveSpaceWasDismissed)"
        )
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
            logger.error(
                "spatial playback transport failed error=\(error.localizedDescription, privacy: .public)"
            )
            return .failed(reason: reason)
        }
    }

    private func restoreTargetPlaybackIntentBeforeSettlement(
        _ execution: Execution,
        restoresPlayerWindowOnFailure: Bool = false
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
                appModel.recordSurfaceInputProbe(
                    "targetPlaybackIntentRestored mediaSession=\(mediaSessionID)"
                )
                return true
            } catch {
                guard setRuntimeIssue(
                    .playbackControlFailed,
                    execution: execution
                ) else {
                    return false
                }
                if restoresPlayerWindowOnFailure {
                    _ = await restorePlaybackWindow(
                        for: normalizeWindowTransition,
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
        case .failed:
            guard setRuntimeIssue(.playbackControlFailed, execution: execution) else {
                return false
            }
            if restoresPlayerWindowOnFailure {
                _ = await restorePlaybackWindow(
                    for: normalizeWindowTransition,
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

    @discardableResult
    private func complete(
        _ execution: Execution,
        outcome: SpatialPlatformEffectOutcome,
        performsAfterTransport: Bool = true,
        failureRecovery: SpatialPlatformPresentationFailureRecovery = .unavailable
    ) async -> SpatialPlatformEffectResolution {
        guard executionIsLive(execution) else { return .ignored }
        if case .failed = outcome {
            let diagnostic = [
                "outcome=\(String(describing: outcome))",
                "operation=\(lastPlatformOperation)",
                "checkpoint=\(lastExecutionCheckpoint)",
                "lifecycle=\(playbackRuntime.productLifecycle.rawValue)",
                "runtime=\(playbackRuntime.userVisibleIssue?.category.rawValue ?? "none")"
            ].joined(separator: ",")
            appModel.recordPresentationConversionDiagnostic(diagnostic)
            logger.error(
                "Playback presentation conversion failed \(diagnostic, privacy: .public)"
            )
            if SpatialPlatformPresentationFailurePolicy.shouldStopPlayback(
                effect: execution.request.effect,
                recovery: failureRecovery
            ) {
                await stopPlaybackForFailedPresentationTransfer()
                appModel.requestStoppedPlaybackCleanup()
                playbackRuntime.setUserVisibleIssue(.presentationConversionFailed)
                lastExecutionResolution =
                    "\(String(describing: outcome))-playback-stopped"
                lastExecutionCheckpoint = "presentation-conversion-failed"
                return .ignored
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

        if let presentationRestoredAfterFailure {
            let restored = await playbackRuntime.waitUntilPresentationSettled(
                to: presentationRestoredAfterFailure
            )
            guard executionIsLive(execution, phase: .settledRequest) else {
                return resolution
            }
            guard restored else {
                await stopPlaybackForFailedPresentationTransfer()
                appModel.requestStoppedPlaybackCleanup()
                playbackRuntime.setUserVisibleIssue(.presentationConversionFailed)
                lastExecutionResolution =
                    "\(String(describing: outcome))-rollback-settlement-failed"
                lastExecutionCheckpoint = "presentation-rollback-settlement-failed"
                return .ignored
            }
            await releaseDepartingPresentationResources()
            lastExecutionCheckpoint =
                "presentation-rollback-settled-\(presentationRestoredAfterFailure.rawValue)"
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

        switch await executePlaybackTransport(
            transportIntent,
            execution: execution,
            phase: .settledRequest
        ) {
        case .succeeded, .invalidated:
            break
        case .failed(let reason):
            guard reason != .mediaSessionChanged,
                  setRuntimeIssue(
                    .playbackControlFailed,
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
public struct SpatialPlatformEffectExecutor: View {
    @Environment(PlaybackSessionModel.self) private var appModel
    @Environment(SpatialPlatformEffectCoordinator.self) private var coordinator
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.pushWindow) private var pushWindow
    @State private var registrationID = UUID()
    private let windowIdentity: SpatialPlatformWindowIdentity?

    public init(windowIdentity: SpatialPlatformWindowIdentity? = nil) {
        self.windowIdentity = windowIdentity
    }

    public var body: some View {
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
