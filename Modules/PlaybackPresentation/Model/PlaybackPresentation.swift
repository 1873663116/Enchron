import Foundation
import Observation
import PlaybackFeature

public enum PlaybackPresentation: String, Codable, CaseIterable, Sendable {
    case window
    case docked
    case panorama
}

public enum SpatialImmersiveSpaceOpeningContext: Equatable, Sendable {
    case environment
    case playback(PlaybackPresentation)
}

public enum SpatialImmersiveSpacePolicy {
    public static let progressiveImmersionRange = 0.3...1.0
    public static let panoramaOpeningInitialAmount = 1.0

    public static func openingInitialAmount(
        for context: SpatialImmersiveSpaceOpeningContext,
        lastObservedAmount: Double?
    ) -> Double? {
        switch context {
        case .environment:
            normalized(lastObservedAmount)
        case .playback(.panorama):
            panoramaOpeningInitialAmount
        case .playback(.window), .playback(.docked):
            normalized(lastObservedAmount)
        }
    }

    public static func normalized(_ amount: Double?) -> Double? {
        guard let amount, amount.isFinite else { return nil }
        return min(
            max(amount, progressiveImmersionRange.lowerBound),
            progressiveImmersionRange.upperBound
        )
    }
}

public enum PlaybackPresentationAvailability {
    public static func canDock(
        in presentation: PlaybackPresentation,
        isPanoramic: Bool
    ) -> Bool {
        presentation == .window && isPanoramic == false
    }

    public static func windowShowsPanoramaResume(
        in presentation: PlaybackPresentation,
        isPanoramic: Bool
    ) -> Bool {
        presentation == .window && isPanoramic
    }

    public static func presentation(afterApplying format: MediaFormat) -> PlaybackPresentation {
        format.projection.isPanoramic ? .panorama : .window
    }
}

public enum PlaybackPrimaryTransportAction: Equatable, Sendable {
    case play
    case pause
    case replay
}

public struct PlaybackTransportAvailability: Equatable, Sendable {
    public let primaryAction: PlaybackPrimaryTransportAction
    public let canSkipForward: Bool
    public let canStepForward: Bool

    public init(lifecycle: ProductPlaybackLifecycle) {
        switch lifecycle {
        case .playing:
            primaryAction = .pause
            canSkipForward = true
            canStepForward = true
        case .ended:
            primaryAction = .replay
            canSkipForward = false
            canStepForward = false
        case .idle, .loading, .ready, .paused, .failed:
            primaryAction = .play
            canSkipForward = true
            canStepForward = true
        }
    }
}

public enum PlaybackScreenSize {
    public static let scaleRange = 0.5...2.5
    public static let scaleStep = 0.05
}

public struct PlaybackDockedPlacement: Equatable, Sendable {
    public static let defaultDistance = 4.0
    public static let defaultElevationDegrees = 0.0
    public static let distanceRange = 0.5...10.0
    public static let distanceStep = 0.1
    public static let elevationRange = -80.0...80.0
    public static let elevationStep = 1.0

    public let distanceMeters: Double
    public let elevationDegrees: Double
    public let screenScale: Double

    public init(
        distanceMeters: Double = Self.defaultDistance,
        elevationDegrees: Double = Self.defaultElevationDegrees,
        screenScale: Double = 1.3
    ) {
        self.distanceMeters = min(
            max(distanceMeters, Self.distanceRange.lowerBound),
            Self.distanceRange.upperBound
        )
        self.elevationDegrees = min(
            max(elevationDegrees, Self.elevationRange.lowerBound),
            Self.elevationRange.upperBound
        )
        self.screenScale = min(
            max(screenScale, PlaybackScreenSize.scaleRange.lowerBound),
            PlaybackScreenSize.scaleRange.upperBound
        )
    }
}

public enum EnvironmentContext: Equatable, Sendable {
    case none
    case active(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    )

    public var environment: SpatialSceneDomain.CinemaEnvironment? {
        guard case .active(let environment, _) = self else { return nil }
        return environment
    }

    public var effect: SpatialSceneDomain.EnvironmentEffect? {
        guard case .active(_, let effect) = self else { return nil }
        return effect
    }

}

public struct PlaybackPresentationTransition: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let previousPresentation: PlaybackPresentation
    public let targetPresentation: PlaybackPresentation
    public let previousEnvironment: EnvironmentContext
    public let targetEnvironment: EnvironmentContext

    public init(
        id: UUID = UUID(),
        previousPresentation: PlaybackPresentation,
        targetPresentation: PlaybackPresentation,
        previousEnvironment: EnvironmentContext,
        targetEnvironment: EnvironmentContext
    ) {
        self.id = id
        self.previousPresentation = previousPresentation
        self.targetPresentation = targetPresentation
        self.previousEnvironment = previousEnvironment
        self.targetEnvironment = targetEnvironment
    }
}

public enum PlaybackPresentationTransitionError: Error, Equatable, Sendable {
    case transitionInFlight
    case platformEffectInFlight
    case mediaSessionRequired
    case alreadyPresented
    case directSpatialTransitionNotSupported
    case dockedPresentationRequiresEnvironment
    case environmentPreviewRequiresWindow
    case environmentCardUnavailableInPanorama
}

public struct SpatialPlaybackTransitionContext: Equatable, Sendable {
    public let mediaSessionID: String
    public let wasPlaying: Bool

    public init(mediaSessionID: String, wasPlaying: Bool) {
        self.mediaSessionID = mediaSessionID
        self.wasPlaying = wasPlaying
    }
}

public enum SpatialPlaybackTransportIntent: Equatable, Sendable {
    case pause(mediaSessionID: String)
    case resume(mediaSessionID: String)

    public var mediaSessionID: String {
        switch self {
        case .pause(let mediaSessionID), .resume(let mediaSessionID):
            mediaSessionID
        }
    }
}

public struct SpatialPlaybackTransportPlan: Equatable, Sendable {
    public let mediaSessionID: String
    public let beforeEffect: SpatialPlaybackTransportIntent?
    public let afterSuccess: SpatialPlaybackTransportIntent?
    public let afterFailure: SpatialPlaybackTransportIntent?

    public init(
        mediaSessionID: String,
        beforeEffect: SpatialPlaybackTransportIntent?,
        afterSuccess: SpatialPlaybackTransportIntent?,
        afterFailure: SpatialPlaybackTransportIntent?
    ) {
        self.mediaSessionID = mediaSessionID
        self.beforeEffect = beforeEffect
        self.afterSuccess = afterSuccess
        self.afterFailure = afterFailure
    }
}

public enum SpatialPlatformEffect: Equatable, Sendable {
    case presentSpatialPlayback(PlaybackPresentation)
    case recoverSpatialPlayback(PlaybackPresentation)
    case presentWindowPlayback(
        keepsEnvironmentOpen: Bool,
        immersiveSpaceAlreadyClosed: Bool
    )
    case presentEnvironmentPreview
    case dismissEnvironmentPreview
    case presentEnvironmentCard
    case normalizeStoppedSpatialPlayback(keepsEnvironmentOpen: Bool)
    case normalizeInvalidatedSpatialPlayback(keepsEnvironmentOpen: Bool)
}

public struct SpatialPlatformEffectRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let effect: SpatialPlatformEffect
    public let playbackTransportPlan: SpatialPlaybackTransportPlan?

    public init(
        id: UUID = UUID(),
        effect: SpatialPlatformEffect,
        playbackTransportPlan: SpatialPlaybackTransportPlan? = nil
    ) {
        self.id = id
        self.effect = effect
        self.playbackTransportPlan = playbackTransportPlan
    }
}

public enum SpatialPlatformEffectFailure: Equatable, Sendable {
    case mediaSessionChanged
    case playbackPauseFailed
    case immersiveSpaceUnavailable
    case spatialPlaybackSurfaceUnavailable
    case rendererReleaseUnavailable
    case windowPlaybackSurfaceUnavailable
    case executionCancelled
}

public enum SpatialPlatformEffectOutcome: Equatable, Sendable {
    case succeeded
    case failed(SpatialPlatformEffectFailure)
}

public struct SpatialPlatformEffectResult: Equatable, Sendable {
    public let requestID: UUID
    public let executionID: UUID
    public let mediaSessionID: String?
    public let outcome: SpatialPlatformEffectOutcome

    public init(
        requestID: UUID,
        executionID: UUID,
        mediaSessionID: String? = nil,
        outcome: SpatialPlatformEffectOutcome
    ) {
        self.requestID = requestID
        self.executionID = executionID
        self.mediaSessionID = mediaSessionID
        self.outcome = outcome
    }
}

public enum SpatialPlatformResultEvent: Equatable, Sendable {
    case effectCompleted(SpatialPlatformEffectResult)
    case effectExecutionAbandoned(requestID: UUID, executionID: UUID)
    case mediaSessionInvalidated(
        requestID: UUID,
        executionID: UUID,
        requiresPlatformNormalization: Bool
    )
    case playbackTransportFailed(SpatialPlaybackTransportFailure)
    case immersiveSpaceAppeared
    case immersiveSpaceDisappeared(SpatialPlaybackTransitionContext?)
    case environmentCardAppeared
    case environmentCardDisappeared
}

public enum SpatialPlatformEffectResolution: Equatable, Sendable {
    case ignored
    case platformFactRecorded
    case effectCompleted
    case presentationCommitted(PlaybackPresentation)
    case presentationRolledBack(SpatialPlatformEffectFailure)
    case spatialRecoveryRequested(PlaybackPresentation)
    case spatialRecoveryCompleted(PlaybackPresentation)
    case spatialRecoveryFailed(SpatialPlatformEffectFailure)
    case playbackTransportFailureRecorded
}

public enum SpatialPlatformImmersiveSpaceResidency: Equatable, Sendable {
    case closed
    case open
}

public enum EnvironmentCardResidency: Equatable, Sendable {
    case closed
    case opening
    case open
}

public enum SpatialPlaybackTransportFailureReason: Equatable, Sendable {
    case mediaSessionChanged
    case operationRejected
}

public struct SpatialPlaybackTransportFailure: Equatable, Sendable {
    public let requestID: UUID
    public let executionID: UUID
    public let mediaSessionID: String
    public let intent: SpatialPlaybackTransportIntent
    public let reason: SpatialPlaybackTransportFailureReason

    public init(
        requestID: UUID,
        executionID: UUID,
        mediaSessionID: String,
        intent: SpatialPlaybackTransportIntent,
        reason: SpatialPlaybackTransportFailureReason
    ) {
        self.requestID = requestID
        self.executionID = executionID
        self.mediaSessionID = mediaSessionID
        self.intent = intent
        self.reason = reason
    }
}

package struct PlaybackPresentationState: Equatable, Sendable {
    package private(set) var presented: PlaybackPresentation
    package private(set) var environment: EnvironmentContext
    package private(set) var transition: PlaybackPresentationTransition?
    package private(set) var environmentBeforeDockedPresentation: EnvironmentContext?

    package init(
        presented: PlaybackPresentation = .window,
        environment: EnvironmentContext = .none
    ) {
        self.presented = presented
        self.environment = environment
        environmentBeforeDockedPresentation = nil
    }

    @discardableResult
    package mutating func begin(
        _ target: PlaybackPresentation,
        effect requestedEffect: SpatialSceneDomain.EnvironmentEffect? = nil,
        defaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .enchron,
        id: UUID = UUID()
    ) throws -> PlaybackPresentationTransition {
        guard transition == nil else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        guard target != presented else {
            throw PlaybackPresentationTransitionError.alreadyPresented
        }
        if presented != .window, target != .window {
            throw PlaybackPresentationTransitionError.directSpatialTransitionNotSupported
        }

        let targetEnvironment: EnvironmentContext
        if target == .docked {
            if let activeEnvironment = environment.environment,
               let activeEffect = environment.effect {
                targetEnvironment = .active(
                    environment: activeEnvironment,
                    effect: activeEffect
                )
            } else {
                targetEnvironment = .active(
                    environment: defaultEnvironment,
                    effect: requestedEffect ?? .inactiveFallback
                )
            }
        } else if presented == .docked, target == .window {
            targetEnvironment = environmentBeforeDockedPresentation ?? .none
        } else {
            targetEnvironment = environment
        }

        let next = PlaybackPresentationTransition(
            id: id,
            previousPresentation: presented,
            targetPresentation: target,
            previousEnvironment: environment,
            targetEnvironment: targetEnvironment
        )
        transition = next
        return next
    }

    package mutating func commit(_ id: UUID) throws {
        guard let transition, transition.id == id else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        if transition.targetPresentation == .docked,
           transition.targetEnvironment.environment == nil {
            throw PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment
        }
        if transition.previousPresentation == .window,
           transition.targetPresentation == .docked {
            environmentBeforeDockedPresentation = transition.previousEnvironment
        } else if transition.previousPresentation == .docked,
                  transition.targetPresentation == .window {
            environmentBeforeDockedPresentation = nil
        }
        presented = transition.targetPresentation
        environment = transition.targetEnvironment
        self.transition = nil
    }

    package mutating func rollback(_ id: UUID) {
        guard let transition, transition.id == id else { return }
        presented = transition.previousPresentation
        environment = transition.previousEnvironment
        self.transition = nil
    }

    package mutating func setEnvironment(_ environment: EnvironmentContext) throws {
        guard transition == nil else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        if presented == .docked, environment.environment == nil {
            throw PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment
        }
        self.environment = environment
    }

    package mutating func resetForPlaybackStop() {
        if let transition {
            rollback(transition.id)
        }
        if presented == .docked {
            environment = environmentBeforeDockedPresentation ?? .none
        }
        presented = .window
        environmentBeforeDockedPresentation = nil
    }

    package mutating func settleSpatialRecoveryFailure() {
        if let transition {
            rollback(transition.id)
        }
        if presented == .docked {
            environment = environmentBeforeDockedPresentation ?? .none
        }
        presented = .window
        environmentBeforeDockedPresentation = nil
    }
}

public enum SpatialRecoveryIntentError: Error, Equatable, Sendable {
    case windowDoesNotRequireSpatialRecovery
}

public struct SpatialRecoveryIntent: Equatable, Sendable {
    public let presentation: PlaybackPresentation
    public let mediaSessionID: String
    public let wasPlaying: Bool

    public init(
        presentation: PlaybackPresentation,
        mediaSessionID: String,
        wasPlaying: Bool
    ) throws {
        guard presentation != .window else {
            throw SpatialRecoveryIntentError.windowDoesNotRequireSpatialRecovery
        }
        self.presentation = presentation
        self.mediaSessionID = mediaSessionID
        self.wasPlaying = wasPlaying
    }
}

public struct PlaybackPresentationSnapshot: Equatable, Sendable {
    public let presentation: PlaybackPresentation
    public let environmentContext: EnvironmentContext
    public let defaultEnvironment: SpatialSceneDomain.CinemaEnvironment
    public let dockedPlacement: PlaybackDockedPlacement
    public let transition: PlaybackPresentationTransition?
    public let pendingSpatialPlatformEffect: SpatialPlatformEffectRequest?
    public let immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency
    public let environmentCardResidency: EnvironmentCardResidency
    public let recoveryIntent: SpatialRecoveryIntent?
    public let lastPlaybackTransportFailure: SpatialPlaybackTransportFailure?
    public let isTransitionExecutionOccupied: Bool
    public let automaticPanoramaEntryPending: Bool
    public let environmentCardEntryPending: Bool
}

@MainActor
@Observable
public final class PlaybackPresentationModel {
    private var presentationState = PlaybackPresentationState()
    private var activeSpatialPlatformEffectID: UUID?
    private var activeSpatialPlatformExecutionID: UUID?
    private var environmentContextBeforePreviewRequest: EnvironmentContext?
    private var environmentCardResidencyBeforeRequest: EnvironmentCardResidency?
    private var lastSettledPlaybackEffectCorrelation:
        (requestID: UUID, executionID: UUID, mediaSessionID: String)?

    public private(set) var defaultEnvironment: SpatialSceneDomain.CinemaEnvironment
    public private(set) var dockedPlacement: PlaybackDockedPlacement
    public private(set) var pendingSpatialPlatformEffect: SpatialPlatformEffectRequest?
    public private(set) var immersiveSpaceResidency:
        SpatialPlatformImmersiveSpaceResidency = .closed
    public private(set) var environmentCardResidency: EnvironmentCardResidency = .closed
    public private(set) var recoveryIntent: SpatialRecoveryIntent?
    public private(set) var lastPlaybackTransportFailure: SpatialPlaybackTransportFailure?
    public private(set) var automaticPanoramaEntryPending = false
    public private(set) var environmentCardEntryPending = false

    @ObservationIgnored
    private let screenPositionStore: any ScreenPositionStoring

    public init(
        defaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .enchron,
        screenPositionStore: any ScreenPositionStoring =
            PlaybackPresentationStorage.makeScreenPositionStore()
    ) {
        self.defaultEnvironment = defaultEnvironment
        dockedPlacement = PlaybackDockedPlacement(
            screenScale: EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: defaultEnvironment.rawValue
            )
        )
        self.screenPositionStore = screenPositionStore
    }

    public var snapshot: PlaybackPresentationSnapshot {
        PlaybackPresentationSnapshot(
            presentation: presentationState.presented,
            environmentContext: presentationState.environment,
            defaultEnvironment: defaultEnvironment,
            dockedPlacement: dockedPlacement,
            transition: presentationState.transition,
            pendingSpatialPlatformEffect: pendingSpatialPlatformEffect,
            immersiveSpaceResidency: immersiveSpaceResidency,
            environmentCardResidency: environmentCardResidency,
            recoveryIntent: recoveryIntent,
            lastPlaybackTransportFailure: lastPlaybackTransportFailure,
            isTransitionExecutionOccupied: activeSpatialPlatformEffectID != nil,
            automaticPanoramaEntryPending: automaticPanoramaEntryPending,
            environmentCardEntryPending: environmentCardEntryPending
        )
    }

    public var presentation: PlaybackPresentation {
        presentationState.presented
    }

    public var environmentContext: EnvironmentContext {
        presentationState.environment
    }

    public var transition: PlaybackPresentationTransition? {
        presentationState.transition
    }

    public var isTransitionExecutionOccupied: Bool {
        activeSpatialPlatformEffectID != nil
    }

    public var currentEnvironment: SpatialSceneDomain.CinemaEnvironment {
        environmentContext.environment ?? defaultEnvironment
    }

    public var currentEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect {
        environmentContext.effect ?? .inactiveFallback
    }

    @discardableResult
    public func requestPresentation(
        _ presentation: PlaybackPresentation,
        effect: SpatialSceneDomain.EnvironmentEffect? = nil,
        playbackContext: SpatialPlaybackTransitionContext
    ) throws -> PlaybackPresentationTransition {
        guard transition == nil else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        guard pendingSpatialPlatformEffect == nil else {
            throw PlaybackPresentationTransitionError.platformEffectInFlight
        }
        guard playbackContext.mediaSessionID.isEmpty == false else {
            throw PlaybackPresentationTransitionError.mediaSessionRequired
        }
        let transition = try presentationState.begin(
            presentation,
            effect: effect,
            defaultEnvironment: defaultEnvironment
        )
        let platformEffect: SpatialPlatformEffect
        if presentation == .window {
            platformEffect = .presentWindowPlayback(
                keepsEnvironmentOpen: transition.targetEnvironment.environment != nil,
                immersiveSpaceAlreadyClosed: false
            )
        } else {
            platformEffect = .presentSpatialPlayback(presentation)
        }
        pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
            effect: platformEffect,
            playbackTransportPlan: playbackTransportPlan(
                for: playbackContext,
                resumesAfterSuccess: automaticPanoramaEntryPending == false
                    && environmentCardEntryPending == false
            )
        )
        lastPlaybackTransportFailure = nil
        return transition
    }

    public func activateEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) throws {
        guard pendingSpatialPlatformEffect == nil else {
            throw PlaybackPresentationTransitionError.platformEffectInFlight
        }
        try presentationState.setEnvironment(
            .active(environment: environment, effect: effect)
        )
    }

    public func deactivateEnvironment() throws {
        guard pendingSpatialPlatformEffect == nil else {
            throw PlaybackPresentationTransitionError.platformEffectInFlight
        }
        try presentationState.setEnvironment(.none)
    }

    public func requestEnvironmentPreview(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) throws {
        guard presentation == .window else {
            throw PlaybackPresentationTransitionError.environmentPreviewRequiresWindow
        }
        guard pendingSpatialPlatformEffect == nil else {
            throw PlaybackPresentationTransitionError.platformEffectInFlight
        }
        environmentContextBeforePreviewRequest = environmentContext
        try presentationState.setEnvironment(
            .active(environment: environment, effect: effect)
        )
        pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
            effect: .presentEnvironmentPreview
        )
    }

    public func requestEnvironmentPreviewDismissal() throws {
        guard presentation == .window else {
            throw PlaybackPresentationTransitionError.environmentPreviewRequiresWindow
        }
        guard pendingSpatialPlatformEffect == nil else {
            throw PlaybackPresentationTransitionError.platformEffectInFlight
        }
        pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
            effect: .dismissEnvironmentPreview
        )
    }

    @discardableResult
    public func requestEnvironmentCard(
        playbackContext: SpatialPlaybackTransitionContext? = nil
    ) throws -> Bool {
        if environmentCardEntryPending
            || pendingSpatialPlatformEffect?.effect == .presentEnvironmentCard
            || environmentCardResidency == .opening {
            return false
        }
        guard pendingSpatialPlatformEffect == nil else {
            throw PlaybackPresentationTransitionError.platformEffectInFlight
        }
        switch presentation {
        case .panorama:
            throw PlaybackPresentationTransitionError.environmentCardUnavailableInPanorama
        case .docked:
            guard let playbackContext,
                  playbackContext.mediaSessionID.isEmpty == false else {
                throw PlaybackPresentationTransitionError.mediaSessionRequired
            }
            environmentCardEntryPending = true
            do {
                _ = try requestPresentation(
                    .window,
                    playbackContext: playbackContext
                )
                return true
            } catch {
                environmentCardEntryPending = false
                throw error
            }
        case .window:
            enqueueEnvironmentCardPresentation()
            return true
        }
    }

    public func configureDefaultEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment
    ) {
        guard transition == nil,
              pendingSpatialPlatformEffect == nil else { return }
        defaultEnvironment = environment
    }

    public func setActiveEnvironmentEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        guard transition == nil,
              pendingSpatialPlatformEffect == nil,
              let environment = environmentContext.environment else { return }
        try? presentationState.setEnvironment(
            .active(environment: environment, effect: effect)
        )
    }

    package func resetForStoppedPlayback() {
        presentationState.resetForPlaybackStop()
        automaticPanoramaEntryPending = false
        environmentCardEntryPending = false
        recoveryIntent = nil
    }

    public func requestStoppedPlaybackCleanup() {
        pendingSpatialPlatformEffect = nil
        activeSpatialPlatformEffectID = nil
        activeSpatialPlatformExecutionID = nil
        environmentContextBeforePreviewRequest = nil
        environmentCardResidencyBeforeRequest = nil
        lastSettledPlaybackEffectCorrelation = nil
        lastPlaybackTransportFailure = nil
        resetForStoppedPlayback()
        pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
            effect: .normalizeStoppedSpatialPlayback(
                keepsEnvironmentOpen: environmentContext.environment != nil
            )
        )
    }

    @discardableResult
    public func claimSpatialPlatformEffect(
        _ requestID: UUID,
        executionID: UUID
    ) -> Bool {
        guard pendingSpatialPlatformEffect?.id == requestID,
              activeSpatialPlatformEffectID == nil else { return false }
        activeSpatialPlatformEffectID = requestID
        activeSpatialPlatformExecutionID = executionID
        return true
    }

    public func isSpatialPlatformEffectCurrent(
        _ requestID: UUID,
        executionID: UUID
    ) -> Bool {
        pendingSpatialPlatformEffect?.id == requestID
            && activeSpatialPlatformEffectID == requestID
            && activeSpatialPlatformExecutionID == executionID
    }

    @discardableResult
    public func receiveSpatialPlatformResult(
        _ event: SpatialPlatformResultEvent
    ) -> SpatialPlatformEffectResolution {
        switch event {
        case .effectExecutionAbandoned(let requestID, let executionID):
            guard pendingSpatialPlatformEffect?.id == requestID,
                  activeSpatialPlatformEffectID == requestID,
                  activeSpatialPlatformExecutionID == executionID else {
                return .ignored
            }
            activeSpatialPlatformEffectID = nil
            activeSpatialPlatformExecutionID = nil
            return .platformFactRecorded
        case .mediaSessionInvalidated(
            let requestID,
            let executionID,
            let requiresPlatformNormalization
        ):
            return settleMediaSessionInvalidation(
                requestID: requestID,
                executionID: executionID,
                requiresPlatformNormalization: requiresPlatformNormalization
            )
        case .environmentCardAppeared:
            environmentCardResidency = .open
            return .platformFactRecorded
        case .environmentCardDisappeared:
            environmentCardResidency = .closed
            return .platformFactRecorded
        case .immersiveSpaceAppeared:
            immersiveSpaceResidency = .open
            return .platformFactRecorded
        case .immersiveSpaceDisappeared(let playbackContext):
            immersiveSpaceResidency = .closed
            guard pendingSpatialPlatformEffect == nil,
                  transition == nil else {
                return .platformFactRecorded
            }
            guard presentation != .window else {
                return .platformFactRecorded
            }
            guard let playbackContext,
                  playbackContext.mediaSessionID.isEmpty == false,
                  let intent = try? SpatialRecoveryIntent(
                    presentation: presentation,
                    mediaSessionID: playbackContext.mediaSessionID,
                    wasPlaying: playbackContext.wasPlaying
                  ) else {
                presentationState.settleSpatialRecoveryFailure()
                automaticPanoramaEntryPending = false
                recoveryIntent = nil
                return .spatialRecoveryFailed(.mediaSessionChanged)
            }
            recoveryIntent = intent
            pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
                effect: .recoverSpatialPlayback(intent.presentation),
                playbackTransportPlan: playbackTransportPlan(
                    for: playbackContext,
                    resumesAfterFailure: false
                )
            )
            return .spatialRecoveryRequested(intent.presentation)
        case .effectCompleted(let result):
            return resolveSpatialPlatformEffect(result)
        case .playbackTransportFailed(let failure):
            guard failure.intent == .resume(mediaSessionID: failure.mediaSessionID),
                  lastSettledPlaybackEffectCorrelation?.requestID == failure.requestID,
                  lastSettledPlaybackEffectCorrelation?.executionID
                    == failure.executionID,
                  lastSettledPlaybackEffectCorrelation?.mediaSessionID
                    == failure.mediaSessionID else {
                return .ignored
            }
            guard lastPlaybackTransportFailure != failure else { return .ignored }
            lastPlaybackTransportFailure = failure
            return .playbackTransportFailureRecorded
        }
    }

    private func settleMediaSessionInvalidation(
        requestID: UUID,
        executionID: UUID,
        requiresPlatformNormalization: Bool
    ) -> SpatialPlatformEffectResolution {
        guard let request = pendingSpatialPlatformEffect,
              request.id == requestID,
              activeSpatialPlatformEffectID == requestID,
              activeSpatialPlatformExecutionID == executionID else {
            return .ignored
        }
        pendingSpatialPlatformEffect = nil
        activeSpatialPlatformEffectID = nil
        activeSpatialPlatformExecutionID = nil
        lastSettledPlaybackEffectCorrelation = nil
        lastPlaybackTransportFailure = nil

        let resolution = failSpatialPlatformEffect(
            request,
            failure: .mediaSessionChanged
        )
        resetForStoppedPlayback()
        if requiresPlatformNormalization {
            pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
                effect: .normalizeInvalidatedSpatialPlayback(
                    keepsEnvironmentOpen: environmentContext.environment != nil
                )
            )
        }
        return resolution
    }

    private func resolveSpatialPlatformEffect(
        _ result: SpatialPlatformEffectResult
    ) -> SpatialPlatformEffectResolution {
        guard let request = pendingSpatialPlatformEffect,
              request.id == result.requestID,
              activeSpatialPlatformEffectID == result.requestID,
              activeSpatialPlatformExecutionID == result.executionID,
              request.playbackTransportPlan?.mediaSessionID
                == result.mediaSessionID else {
            return .ignored
        }
        pendingSpatialPlatformEffect = nil
        activeSpatialPlatformEffectID = nil
        activeSpatialPlatformExecutionID = nil
        if let mediaSessionID = request.playbackTransportPlan?.mediaSessionID {
            lastSettledPlaybackEffectCorrelation = (
                requestID: request.id,
                executionID: result.executionID,
                mediaSessionID: mediaSessionID
            )
        } else {
            lastSettledPlaybackEffectCorrelation = nil
        }

        switch result.outcome {
        case .succeeded:
            return completeSpatialPlatformEffect(request)
        case .failed(let failure):
            return failSpatialPlatformEffect(request, failure: failure)
        }
    }

    private func completeSpatialPlatformEffect(
        _ request: SpatialPlatformEffectRequest
    ) -> SpatialPlatformEffectResolution {
        switch request.effect {
        case .presentSpatialPlayback:
            immersiveSpaceResidency = .open
            return commitPendingPresentation()
        case .recoverSpatialPlayback(let presentation):
            immersiveSpaceResidency = .open
            recoveryIntent = nil
            return .spatialRecoveryCompleted(presentation)
        case .presentWindowPlayback(let keepsEnvironmentOpen, _):
            immersiveSpaceResidency = keepsEnvironmentOpen ? .open : .closed
            let resolution = commitPendingPresentation()
            if automaticPanoramaEntryPending, presentation == .window {
                automaticPanoramaEntryPending = false
                if let playbackContext = playbackContext(for: request) {
                    _ = try? requestPresentation(
                        .panorama,
                        playbackContext: playbackContext
                    )
                }
            } else if environmentCardEntryPending, presentation == .window {
                environmentCardEntryPending = false
                if let playbackContext = playbackContext(for: request) {
                    enqueueEnvironmentCardPresentation(
                        playbackTransportPlan: continuationPlaybackTransportPlan(
                            for: playbackContext
                        )
                    )
                } else {
                    enqueueEnvironmentCardPresentation()
                }
            }
            return resolution
        case .presentEnvironmentPreview:
            environmentContextBeforePreviewRequest = nil
            immersiveSpaceResidency = .open
            return .effectCompleted
        case .dismissEnvironmentPreview:
            try? presentationState.setEnvironment(.none)
            immersiveSpaceResidency = .closed
            return .effectCompleted
        case .presentEnvironmentCard:
            environmentCardResidencyBeforeRequest = nil
            return .effectCompleted
        case .normalizeStoppedSpatialPlayback(let keepsEnvironmentOpen):
            immersiveSpaceResidency = keepsEnvironmentOpen ? .open : .closed
            return .effectCompleted
        case .normalizeInvalidatedSpatialPlayback(let keepsEnvironmentOpen):
            immersiveSpaceResidency = keepsEnvironmentOpen ? .open : .closed
            return .effectCompleted
        }
    }

    private func failSpatialPlatformEffect(
        _ request: SpatialPlatformEffectRequest,
        failure: SpatialPlatformEffectFailure
    ) -> SpatialPlatformEffectResolution {
        switch request.effect {
        case .presentSpatialPlayback, .presentWindowPlayback:
            if let transition {
                presentationState.rollback(transition.id)
            }
            if case .presentWindowPlayback = request.effect {
                automaticPanoramaEntryPending = false
                environmentCardEntryPending = false
            }
            return .presentationRolledBack(failure)
        case .recoverSpatialPlayback:
            recoveryIntent = nil
            automaticPanoramaEntryPending = false
            immersiveSpaceResidency = .closed
            presentationState.settleSpatialRecoveryFailure()
            return .spatialRecoveryFailed(failure)
        case .presentEnvironmentPreview:
            if let environmentContextBeforePreviewRequest {
                try? presentationState.setEnvironment(environmentContextBeforePreviewRequest)
            }
            self.environmentContextBeforePreviewRequest = nil
            immersiveSpaceResidency = .closed
            return .effectCompleted
        case .dismissEnvironmentPreview,
             .normalizeStoppedSpatialPlayback,
             .normalizeInvalidatedSpatialPlayback:
            return .effectCompleted
        case .presentEnvironmentCard:
            if environmentCardResidency != .open,
               let environmentCardResidencyBeforeRequest {
                environmentCardResidency = environmentCardResidencyBeforeRequest
            }
            self.environmentCardResidencyBeforeRequest = nil
            return .effectCompleted
        }
    }

    private func commitPendingPresentation() -> SpatialPlatformEffectResolution {
        guard let transition else { return .ignored }
        do {
            try presentationState.commit(transition.id)
            return .presentationCommitted(transition.targetPresentation)
        } catch {
            presentationState.rollback(transition.id)
            return .presentationRolledBack(.executionCancelled)
        }
    }

    public func setAutomaticPanoramaEntryPending(_ pending: Bool) {
        automaticPanoramaEntryPending = pending
    }

    private func enqueueEnvironmentCardPresentation(
        playbackTransportPlan: SpatialPlaybackTransportPlan? = nil
    ) {
        environmentCardResidencyBeforeRequest = environmentCardResidency
        if environmentCardResidency == .closed {
            environmentCardResidency = .opening
        }
        pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
            effect: .presentEnvironmentCard,
            playbackTransportPlan: playbackTransportPlan
        )
    }

    private func playbackTransportPlan(
        for context: SpatialPlaybackTransitionContext,
        resumesAfterSuccess: Bool = true,
        resumesAfterFailure: Bool = true
    ) -> SpatialPlaybackTransportPlan {
        let pause: SpatialPlaybackTransportIntent? = context.wasPlaying
            ? .pause(mediaSessionID: context.mediaSessionID)
            : nil
        let resume: SpatialPlaybackTransportIntent? = context.wasPlaying
            ? .resume(mediaSessionID: context.mediaSessionID)
            : nil
        return SpatialPlaybackTransportPlan(
            mediaSessionID: context.mediaSessionID,
            beforeEffect: pause,
            afterSuccess: resumesAfterSuccess ? resume : nil,
            afterFailure: resumesAfterFailure ? resume : nil
        )
    }

    private func continuationPlaybackTransportPlan(
        for context: SpatialPlaybackTransitionContext
    ) -> SpatialPlaybackTransportPlan {
        let resume: SpatialPlaybackTransportIntent? = context.wasPlaying
            ? .resume(mediaSessionID: context.mediaSessionID)
            : nil
        return SpatialPlaybackTransportPlan(
            mediaSessionID: context.mediaSessionID,
            beforeEffect: nil,
            afterSuccess: resume,
            afterFailure: resume
        )
    }

    private func playbackContext(
        for request: SpatialPlatformEffectRequest
    ) -> SpatialPlaybackTransitionContext? {
        guard let plan = request.playbackTransportPlan else { return nil }
        return SpatialPlaybackTransitionContext(
            mediaSessionID: plan.mediaSessionID,
            wasPlaying: plan.beforeEffect != nil
        )
    }

    public func loadDockedPlacement() async {
        let environmentID = currentEnvironment.rawValue
        guard let saved = await screenPositionStore.loadPosition(for: environmentID),
              currentEnvironment.rawValue == environmentID else {
            if currentEnvironment.rawValue == environmentID {
                dockedPlacement = defaultDockedPlacement(for: currentEnvironment)
            }
            return
        }
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: saved.distanceMeters,
            elevationDegrees: saved.elevationDegrees,
            screenScale: saved.screenScale
        )
    }

    public func setScreenScale(_ scale: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: dockedPlacement.distanceMeters,
            elevationDegrees: dockedPlacement.elevationDegrees,
            screenScale: scale
        )
        saveDockedPlacement()
    }

    public func setScreenDistance(_ distance: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: distance,
            elevationDegrees: dockedPlacement.elevationDegrees,
            screenScale: dockedPlacement.screenScale
        )
        saveDockedPlacement()
    }

    public func setScreenElevation(_ elevationDegrees: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: dockedPlacement.distanceMeters,
            elevationDegrees: elevationDegrees,
            screenScale: dockedPlacement.screenScale
        )
        saveDockedPlacement()
    }

    public func resetDockedPlacement() {
        dockedPlacement = defaultDockedPlacement(for: currentEnvironment)
        saveDockedPlacement()
    }

    public func saveDockedPlacement() {
        let environmentID = currentEnvironment.rawValue
        let placement = dockedPlacement
        let store = screenPositionStore
        Task.detached(priority: .utility) {
            await store.savePosition(
                for: environmentID,
                distanceMeters: placement.distanceMeters,
                elevationDegrees: placement.elevationDegrees,
                screenScale: placement.screenScale
            )
        }
    }

    private func defaultDockedPlacement(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> PlaybackDockedPlacement {
        PlaybackDockedPlacement(
            screenScale: EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: environment.rawValue
            )
        )
    }
}
