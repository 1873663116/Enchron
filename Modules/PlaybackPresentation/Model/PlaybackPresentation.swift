import Foundation
import Observation
import PlaybackFeature

public enum PresentationContentFamily: Equatable, Sendable {
    case flat
    case panoramic
}

public enum PresentationEdge: Equatable, Sendable {
    case inPlace
    case enterImmersive
    case exitImmersive
    case projectionSwap
    case illegal
}

public enum PlaybackPresentation: String, Codable, CaseIterable, Sendable {
    case window
    case portal
    case docked
    case panorama

    public var usesMainWindow: Bool { self == .window || self == .portal }
    public var usesImmersiveSpace: Bool { self == .docked || self == .panorama }

    public var contentFamily: PresentationContentFamily {
        switch self {
        case .window, .docked:
            .flat
        case .portal, .panorama:
            .panoramic
        }
    }

    public var enterImmersiveTarget: PlaybackPresentation? {
        guard usesMainWindow else { return nil }
        return contentFamily.immersivePresentation
    }

    public var exitImmersiveTarget: PlaybackPresentation? {
        guard usesImmersiveSpace else { return nil }
        return contentFamily.mainWindowPresentation
    }

    public static func edge(
        from source: PlaybackPresentation,
        to target: PlaybackPresentation
    ) -> PresentationEdge {
        switch (
            source.contentFamily == target.contentFamily,
            source.usesImmersiveSpace,
            target.usesImmersiveSpace
        ) {
        case (true, false, false), (true, true, true):
            .inPlace
        case (true, false, true):
            .enterImmersive
        case (true, true, false):
            .exitImmersive
        case (false, false, false):
            .projectionSwap
        case (false, _, _):
            .illegal
        }
    }
}

extension PresentationContentFamily {
    public var mainWindowPresentation: PlaybackPresentation {
        switch self {
        case .flat:
            .window
        case .panoramic:
            .portal
        }
    }

    public var immersivePresentation: PlaybackPresentation {
        switch self {
        case .flat:
            .docked
        case .panoramic:
            .panorama
        }
    }
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
        case .playback(.window), .playback(.portal), .playback(.docked):
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
    public static func presentation(afterApplying format: MediaFormat) -> PlaybackPresentation {
        format.projection.isPanoramic ? .portal : .window
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
    public static let elevationRange = -80.0...80.0
    public static let distanceStep = 0.5
    public static let elevationStep = 5.0

    public let distanceMeters: Double
    public let elevationDegrees: Double
    public let screenScale: Double

    public init(
        distanceMeters: Double = Self.defaultDistance,
        elevationDegrees: Double = Self.defaultElevationDegrees,
        screenScale: Double = 1.3
    ) {
        self.distanceMeters = Self.snapped(
            distanceMeters,
            in: Self.distanceRange,
            step: Self.distanceStep
        )
        self.elevationDegrees = Self.snapped(
            elevationDegrees,
            in: Self.elevationRange,
            step: Self.elevationStep
        )
        self.screenScale = Self.snapped(
            screenScale,
            in: PlaybackScreenSize.scaleRange,
            step: PlaybackScreenSize.scaleStep
        )
    }

    public static func snapped(
        _ value: Double,
        in range: ClosedRange<Double>,
        step: Double
    ) -> Double {
        let span = range.upperBound - range.lowerBound
        let safeStep = step > 0 ? step : span
        let index = ((value - range.lowerBound) / safeStep).rounded()
        let snapped = range.lowerBound + index * safeStep
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

public enum EnvironmentContext: Equatable, Sendable {
    case none
    case active(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
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
    case illegalEdge(
        source: PlaybackPresentation,
        target: PlaybackPresentation
    )
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
    case enterImmersivePlayback(PresentationContentFamily)
    case exitImmersivePlayback(
        PresentationContentFamily,
        keepsEnvironmentOpen: Bool
    )
    case collapseImmersivePlayback(PresentationContentFamily)
    case swapWindowPlaybackProjection(to: PresentationContentFamily)
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
    case immersiveViewingModeUnavailable
    case spatialPlaybackSurfaceUnavailable
    case mainWindowUnavailable
    case playerControlsWindowUnavailable
    case environmentCardDismissalUnavailable
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
    package private(set) var environmentBeforePanoramaPresentation: EnvironmentContext?

    package init(
        presented: PlaybackPresentation = .window,
        environment: EnvironmentContext = .none
    ) {
        self.presented = presented
        self.environment = environment
        environmentBeforeDockedPresentation = nil
        environmentBeforePanoramaPresentation = nil
    }

    @discardableResult
    package mutating func begin(
        _ target: PlaybackPresentation,
        environment requestedEnvironment: SpatialSceneDomain.CinemaEnvironment? = nil,
        effect requestedEffect: SpatialSceneDomain.EnvironmentEffect? = nil,
        defaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .defaultScenic,
        id: UUID = UUID()
    ) throws -> PlaybackPresentationTransition {
        guard transition == nil else {
            throw PlaybackPresentationTransitionError.transitionInFlight
        }
        guard target != presented else {
            throw PlaybackPresentationTransitionError.alreadyPresented
        }

        let targetEnvironment: EnvironmentContext
        if target == .docked {
            let dockingEnvironment = requestedEnvironment ?? defaultEnvironment
            targetEnvironment = .active(
                environment: dockingEnvironment,
                effect: dockingEnvironment.isScenic
                    ? requestedEffect ?? .inactiveFallback
                    : nil
            )
        } else if target == .panorama {
            targetEnvironment = .none
        } else if presented == .docked, target == .window {
            targetEnvironment = environmentBeforeDockedPresentation ?? .none
        } else if presented == .panorama, target.usesMainWindow {
            targetEnvironment = environmentBeforePanoramaPresentation ?? .none
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
        if transition.previousPresentation.usesMainWindow,
           transition.targetPresentation == .panorama {
            environmentBeforePanoramaPresentation = transition.previousEnvironment
        } else if transition.previousPresentation == .panorama,
                  transition.targetPresentation.usesMainWindow {
            environmentBeforePanoramaPresentation = nil
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

    package mutating func recordImmersiveSpaceDisappearance() {
        environment = .none
        environmentBeforeDockedPresentation = nil
        environmentBeforePanoramaPresentation = nil
        guard let transition,
              transition.previousPresentation.usesImmersiveSpace else {
            return
        }
        self.transition = PlaybackPresentationTransition(
            id: transition.id,
            previousPresentation: transition.previousPresentation,
            targetPresentation: transition.targetPresentation,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
    }

    @discardableResult
    package mutating func beginImmersiveSpaceClosureCollapse(
        id: UUID = UUID()
    ) -> PlaybackPresentationTransition? {
        guard transition == nil,
              let target = presented.exitImmersiveTarget else {
            return nil
        }
        let next = PlaybackPresentationTransition(
            id: id,
            previousPresentation: presented,
            targetPresentation: target,
            previousEnvironment: .none,
            targetEnvironment: .none
        )
        transition = next
        return next
    }

    package mutating func resetForPlaybackStop() {
        if let transition {
            rollback(transition.id)
        }
        if presented == .docked {
            environment = environmentBeforeDockedPresentation ?? .none
        } else if presented == .panorama {
            environment = environmentBeforePanoramaPresentation ?? .none
        }
        presented = .window
        environmentBeforeDockedPresentation = nil
        environmentBeforePanoramaPresentation = nil
    }

    package mutating func prepareColdPlaybackLaunch(
        for family: PresentationContentFamily
    ) {
        resetForPlaybackStop()
        presented = family.mainWindowPresentation
        environment = .none
    }

}

public struct PlaybackPresentationSnapshot: Equatable, Sendable {
    public let presentation: PlaybackPresentation
    public let environmentContext: EnvironmentContext
    public let panoramaReturnEnvironmentContext: EnvironmentContext?
    public let defaultEnvironment: SpatialSceneDomain.CinemaEnvironment
    public let dockedPlacement: PlaybackDockedPlacement
    public let transition: PlaybackPresentationTransition?
    public let pendingSpatialPlatformEffect: SpatialPlatformEffectRequest?
    public let immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency
    public let environmentCardResidency: EnvironmentCardResidency
    public let lastPlaybackTransportFailure: SpatialPlaybackTransportFailure?
    public let isTransitionExecutionOccupied: Bool
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
    public private(set) var lastPlaybackTransportFailure: SpatialPlaybackTransportFailure?
    public private(set) var environmentCardEntryPending = false

    @ObservationIgnored
    private let screenPositionStore: any ScreenPositionStoring

    public init(
        defaultEnvironment: SpatialSceneDomain.CinemaEnvironment = .defaultScenic,
        screenPositionStore: any ScreenPositionStoring =
            PlaybackPresentationStorage.makeScreenPositionStore()
    ) {
        let resolvedDefault = defaultEnvironment.isScenic
            ? defaultEnvironment
            : .defaultScenic
        self.defaultEnvironment = resolvedDefault
        dockedPlacement = PlaybackDockedPlacement(
            screenScale: EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: resolvedDefault.rawValue
            )
        )
        self.screenPositionStore = screenPositionStore
    }

    public var snapshot: PlaybackPresentationSnapshot {
        PlaybackPresentationSnapshot(
            presentation: presentationState.presented,
            environmentContext: presentationState.environment,
            panoramaReturnEnvironmentContext:
                presentationState.environmentBeforePanoramaPresentation,
            defaultEnvironment: defaultEnvironment,
            dockedPlacement: dockedPlacement,
            transition: presentationState.transition,
            pendingSpatialPlatformEffect: pendingSpatialPlatformEffect,
            immersiveSpaceResidency: immersiveSpaceResidency,
            environmentCardResidency: environmentCardResidency,
            lastPlaybackTransportFailure: lastPlaybackTransportFailure,
            isTransitionExecutionOccupied: activeSpatialPlatformEffectID != nil,
            environmentCardEntryPending: environmentCardEntryPending
        )
    }

    public var presentation: PlaybackPresentation {
        presentationState.presented
    }

    public var environmentContext: EnvironmentContext {
        presentationState.environment
    }

    public var panoramaReturnEnvironmentContext: EnvironmentContext? {
        presentationState.environmentBeforePanoramaPresentation
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
        environment: SpatialSceneDomain.CinemaEnvironment? = nil,
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
        let source = presentationState.presented
        let edge = PlaybackPresentation.edge(from: source, to: presentation)
        switch edge {
        case .inPlace:
            throw PlaybackPresentationTransitionError.alreadyPresented
        case .illegal:
            throw PlaybackPresentationTransitionError.illegalEdge(
                source: source,
                target: presentation
            )
        case .enterImmersive, .exitImmersive, .projectionSwap:
            break
        }
        let transition = try presentationState.begin(
            presentation,
            environment: environment,
            effect: effect,
            defaultEnvironment: defaultEnvironment
        )
        let platformEffect: SpatialPlatformEffect = switch edge {
        case .enterImmersive:
            .enterImmersivePlayback(presentation.contentFamily)
        case .exitImmersive:
            .exitImmersivePlayback(
                presentation.contentFamily,
                keepsEnvironmentOpen: transition.targetEnvironment.environment != nil
            )
        case .projectionSwap:
            .swapWindowPlaybackProjection(to: presentation.contentFamily)
        case .inPlace, .illegal:
            preconditionFailure("Rejected presentation edge reached effect construction.")
        }
        pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
            effect: platformEffect,
            playbackTransportPlan: playbackTransportPlan(for: playbackContext)
        )
        lastPlaybackTransportFailure = nil
        return transition
    }

    public func activateEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
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
        effect: SpatialSceneDomain.EnvironmentEffect?
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
        case .portal, .panorama:
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
        guard environment.isScenic else { return }
        guard transition == nil,
              pendingSpatialPlatformEffect == nil else { return }
        defaultEnvironment = environment
    }

    public func setActiveEnvironmentEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        guard transition == nil,
              pendingSpatialPlatformEffect == nil,
              let environment = environmentContext.environment,
              environment.isScenic else { return }
        try? presentationState.setEnvironment(
            .active(environment: environment, effect: effect)
        )
    }

    package func resetForStoppedPlayback() {
        presentationState.resetForPlaybackStop()
        environmentCardEntryPending = false
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

    public func prepareColdPlaybackLaunch(
        for family: PresentationContentFamily
    ) {
        guard pendingSpatialPlatformEffect == nil,
              activeSpatialPlatformEffectID == nil else { return }
        presentationState.prepareColdPlaybackLaunch(for: family)
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
            presentationState.recordImmersiveSpaceDisappearance()
            guard pendingSpatialPlatformEffect == nil,
                  transition == nil else {
                return .platformFactRecorded
            }
            guard presentation.usesImmersiveSpace else {
                return .platformFactRecorded
            }
            guard let playbackContext,
                  playbackContext.mediaSessionID.isEmpty == false else {
                resetForStoppedPlayback()
                return .platformFactRecorded
            }
            let family = presentation.contentFamily
            guard presentationState.beginImmersiveSpaceClosureCollapse()
                != nil else {
                return .platformFactRecorded
            }
            pendingSpatialPlatformEffect = SpatialPlatformEffectRequest(
                effect: .collapseImmersivePlayback(family),
                playbackTransportPlan: playbackTransportPlan(for: playbackContext)
            )
            return .platformFactRecorded
        case .effectCompleted(let result):
            return resolveSpatialPlatformEffect(result)
        case .playbackTransportFailed:
            return .ignored
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
        case .enterImmersivePlayback:
            immersiveSpaceResidency = .open
            return commitPendingPresentation()
        case .exitImmersivePlayback(_, let keepsEnvironmentOpen):
            if keepsEnvironmentOpen == false {
                immersiveSpaceResidency = .closed
            }
            let resolution = commitPendingPresentation()
            if environmentCardEntryPending, presentation == .window {
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
        case .collapseImmersivePlayback:
            immersiveSpaceResidency = .closed
            return commitPendingPresentation()
        case .swapWindowPlaybackProjection:
            return commitPendingPresentation()
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
            if keepsEnvironmentOpen == false {
                immersiveSpaceResidency = .closed
            }
            return .effectCompleted
        case .normalizeInvalidatedSpatialPlayback(let keepsEnvironmentOpen):
            if keepsEnvironmentOpen == false {
                immersiveSpaceResidency = .closed
            }
            return .effectCompleted
        }
    }

    private func failSpatialPlatformEffect(
        _ request: SpatialPlatformEffectRequest,
        failure: SpatialPlatformEffectFailure
    ) -> SpatialPlatformEffectResolution {
        switch request.effect {
        case .enterImmersivePlayback,
             .exitImmersivePlayback,
             .collapseImmersivePlayback,
             .swapWindowPlaybackProjection:
            if let transition {
                presentationState.rollback(transition.id)
            }
            if case .exitImmersivePlayback = request.effect {
                environmentCardEntryPending = false
            }
            return .presentationRolledBack(failure)
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
        for context: SpatialPlaybackTransitionContext
    ) -> SpatialPlaybackTransportPlan {
        return SpatialPlaybackTransportPlan(
            mediaSessionID: context.mediaSessionID,
            beforeEffect: nil,
            afterSuccess: context.wasPlaying
                ? .resume(mediaSessionID: context.mediaSessionID)
                : nil,
            afterFailure: nil
        )
    }

    private func continuationPlaybackTransportPlan(
        for context: SpatialPlaybackTransitionContext
    ) -> SpatialPlaybackTransportPlan {
        return SpatialPlaybackTransportPlan(
            mediaSessionID: context.mediaSessionID,
            beforeEffect: nil,
            afterSuccess: nil,
            afterFailure: nil
        )
    }

    private func playbackContext(
        for request: SpatialPlatformEffectRequest
    ) -> SpatialPlaybackTransitionContext? {
        guard let plan = request.playbackTransportPlan else { return nil }
        return SpatialPlaybackTransitionContext(
            mediaSessionID: plan.mediaSessionID,
            wasPlaying: plan.afterSuccess != nil
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
