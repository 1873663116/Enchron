import EnvironmentSceneContract
import Foundation
import Observation

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
        case (true, true, false), (false, true, false):
            .exitImmersive
        case (false, false, false):
            .projectionSwap
        case (false, _, true):
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

public enum PlaybackPrimaryTransportAction: String, Equatable, Sendable {
    case play
    case pause
    case replay
    case playNext
}

public enum PlaybackEndedAffordance: Equatable, Sendable {
    case replay
    case playNext(available: Bool)
}

public struct PlaybackTransportAvailability: Equatable, Sendable {
    public let primaryAction: PlaybackPrimaryTransportAction
    public let primaryActionEnabled: Bool
    public let canSkipForward: Bool
    public let canStepForward: Bool

    public init(
        lifecycle: ProductPlaybackLifecycle,
        endedAffordance: PlaybackEndedAffordance = .replay
    ) {
        switch lifecycle {
        case .playing:
            primaryAction = .pause
            primaryActionEnabled = true
            canSkipForward = true
            canStepForward = true
        case .ended:
            switch endedAffordance {
            case .replay:
                primaryAction = .replay
                primaryActionEnabled = true
            case .playNext(let available):
                primaryAction = .playNext
                primaryActionEnabled = available
            }
            canSkipForward = false
            canStepForward = false
        case .idle, .loading, .ready, .paused, .failed:
            primaryAction = .play
            primaryActionEnabled = true
            canSkipForward = true
            canStepForward = true
        }
    }
}

nonisolated public struct PlaybackDockedPlacementLimits: Equatable, Sendable {
    public static let distanceStep = 0.5
    public static let elevationStep = 5.0
    public static let screenHeightStep = 0.25
    public static let viewerHeightStep = 0.1
    public static let viewerHeightRangeMeters: ClosedRange<Double> = -2...2

    public let distanceRange: ClosedRange<Double>
    public let elevationRange: ClosedRange<Double>
    public let screenHeightRange: ClosedRange<Double>
    public let defaultDistance: Double
    public let defaultElevationDegrees: Double
    public let defaultScreenHeight: Double
    public let viewerHeightRange: ClosedRange<Double>
    public let defaultViewerHeight: Double

    public init(
        distanceRange: ClosedRange<Double>,
        elevationRange: ClosedRange<Double>,
        screenHeightRange: ClosedRange<Double>,
        defaultDistance: Double,
        defaultElevationDegrees: Double = 0,
        defaultScreenHeight: Double,
        viewerHeightRange: ClosedRange<Double> = PlaybackDockedPlacementLimits.viewerHeightRangeMeters,
        defaultViewerHeight: Double = 0
    ) {
        self.distanceRange = distanceRange
        self.elevationRange = elevationRange
        self.screenHeightRange = screenHeightRange
        self.defaultDistance = defaultDistance
        self.defaultElevationDegrees = defaultElevationDegrees
        self.defaultScreenHeight = defaultScreenHeight
        self.viewerHeightRange = viewerHeightRange
        self.defaultViewerHeight = defaultViewerHeight
    }

    public init(geometry: EnvironmentSceneGeometry) {
        self.init(
            distanceRange: geometry.distanceRangeMeters,
            elevationRange: geometry.elevationRangeDegrees,
            screenHeightRange: geometry.screenHeightRangeMeters,
            defaultDistance: geometry.defaultDistanceMeters,
            defaultScreenHeight: geometry.defaultScreenHeightMeters,
            viewerHeightRange: geometry.viewerHeightRangeMeters,
            defaultViewerHeight: geometry.defaultViewerHeightMeters
        )
    }

    public static let fallback = PlaybackDockedPlacementLimits(
        geometry: EnvironmentSceneMapping.placeholderDescriptor.geometry
    )

    public static func limits(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> PlaybackDockedPlacementLimits {
        PlaybackDockedPlacementLimits(geometry: EnvironmentSceneMapping.geometry(for: environment))
    }
}

nonisolated public struct PlaybackDockedPlacement: Equatable, Sendable {
    public let distanceMeters: Double
    public let elevationDegrees: Double
    public let screenScale: Double
    public let viewerHeightMeters: Double
    public let limits: PlaybackDockedPlacementLimits

    public init(
        distanceMeters: Double? = nil,
        elevationDegrees: Double? = nil,
        screenScale: Double? = nil,
        viewerHeightMeters: Double? = nil,
        limits: PlaybackDockedPlacementLimits = .fallback
    ) {
        self.limits = limits
        self.distanceMeters = Self.snapped(
            distanceMeters ?? limits.defaultDistance,
            in: limits.distanceRange,
            step: PlaybackDockedPlacementLimits.distanceStep
        )
        self.elevationDegrees = Self.snapped(
            elevationDegrees ?? limits.defaultElevationDegrees,
            in: limits.elevationRange,
            step: PlaybackDockedPlacementLimits.elevationStep
        )
        self.screenScale = Self.snapped(
            screenScale ?? limits.defaultScreenHeight,
            in: limits.screenHeightRange,
            step: PlaybackDockedPlacementLimits.screenHeightStep
        )
        self.viewerHeightMeters = Self.snapped(
            viewerHeightMeters ?? limits.defaultViewerHeight,
            in: limits.viewerHeightRange,
            step: PlaybackDockedPlacementLimits.viewerHeightStep
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
            guard let dockingEnvironment = requestedEnvironment else {
                throw PlaybackPresentationTransitionError.dockedPresentationRequiresEnvironment
            }
            targetEnvironment = .active(
                environment: dockingEnvironment,
                effect: dockingEnvironment.supportsDarkAppearance
                    ? requestedEffect ?? .inactiveFallback
                    : nil
            )
        } else if target == .panorama {
            targetEnvironment = .none
        } else if presented == .docked, target.usesMainWindow {
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
                  transition.targetPresentation.usesMainWindow {
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

    package mutating func resetForPlaybackStop(closesEnvironment: Bool = false) {
        if let transition {
            rollback(transition.id)
        }
        if presented == .docked {
            environment = environmentBeforeDockedPresentation ?? .none
        } else if presented == .panorama {
            environment = environmentBeforePanoramaPresentation ?? .none
        }
        presented = .window
        if closesEnvironment {
            environment = .none
        }
        environmentBeforeDockedPresentation = nil
        environmentBeforePanoramaPresentation = nil
    }

    package mutating func prepareColdPlaybackLaunch(
        for family: PresentationContentFamily
    ) {
        resetForPlaybackStop()
        presented = family.mainWindowPresentation
    }

}

public struct PlaybackPresentationSnapshot: Equatable, Sendable {
    public let presentation: PlaybackPresentation
    public let environmentContext: EnvironmentContext
    public let panoramaReturnEnvironmentContext: EnvironmentContext?
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
    private var presentationState = PlaybackPresentationState() {
        didSet {
            if presentationState.environment != oldValue.environment {
                Task { await self.loadDockedPlacement() }
            }
        }
    }
    private var activeSpatialPlatformEffectID: UUID?
    private var activeSpatialPlatformExecutionID: UUID?
    private var environmentContextBeforePreviewRequest: EnvironmentContext?
    private var environmentCardResidencyBeforeRequest: EnvironmentCardResidency?
    private var lastSettledPlaybackEffectCorrelation:
        (requestID: UUID, executionID: UUID, mediaSessionID: String)?

    public private(set) var defaultCardEnvironment: SpatialSceneDomain.CinemaEnvironment

    @ObservationIgnored private let environmentDefaults: UserDefaults
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
        screenPositionStore: any ScreenPositionStoring =
            PlaybackPresentationStorage.makeScreenPositionStore(),
        environmentDefaults: UserDefaults = .standard
    ) {
        dockedPlacement = PlaybackDockedPlacement(
            limits: .limits(for: .quietRoom)
        )
        self.screenPositionStore = screenPositionStore
        self.environmentDefaults = environmentDefaults
        let savedEnvironment = environmentDefaults.string(forKey: "defaultCardEnvironment")
            .flatMap(SpatialSceneDomain.CinemaEnvironment.init(rawValue:))
        defaultCardEnvironment = savedEnvironment.flatMap { $0.isCardEnvironment ? $0 : nil } ?? .ocean
    }

    public var snapshot: PlaybackPresentationSnapshot {
        PlaybackPresentationSnapshot(
            presentation: presentationState.presented,
            environmentContext: presentationState.environment,
            panoramaReturnEnvironmentContext:
                presentationState.environmentBeforePanoramaPresentation,
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
        environmentContext.environment ?? .quietRoom
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
            effect: effect
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

    public func setDefaultCardEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment
    ) {
        guard environment.isCardEnvironment else { return }
        defaultCardEnvironment = environment
        environmentDefaults.set(environment.rawValue, forKey: "defaultCardEnvironment")
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

    public func setActiveEnvironmentEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        guard transition == nil,
              pendingSpatialPlatformEffect == nil,
              let environment = environmentContext.environment,
              environment.supportsDarkAppearance else { return }
        try? presentationState.setEnvironment(
            .active(environment: environment, effect: effect)
        )
    }

    package func resetForStoppedPlayback(closesEnvironment: Bool = false) {
        presentationState.resetForPlaybackStop(closesEnvironment: closesEnvironment)
        environmentCardEntryPending = false
    }

    public func requestStoppedPlaybackCleanup(closesEnvironment: Bool = false) {
        pendingSpatialPlatformEffect = nil
        activeSpatialPlatformEffectID = nil
        activeSpatialPlatformExecutionID = nil
        environmentContextBeforePreviewRequest = nil
        environmentCardResidencyBeforeRequest = nil
        lastSettledPlaybackEffectCorrelation = nil
        lastPlaybackTransportFailure = nil
        resetForStoppedPlayback(closesEnvironment: closesEnvironment)
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
        case .collapseImmersivePlayback:
            immersiveSpaceResidency = .closed
            return commitPendingPresentation()
        case .enterImmersivePlayback,
             .exitImmersivePlayback,
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
            screenScale: saved.screenScale,
            viewerHeightMeters: saved.viewerHeightMeters,
            limits: .limits(for: currentEnvironment)
        )
    }

    public func setScreenScale(_ scale: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: dockedPlacement.distanceMeters,
            elevationDegrees: dockedPlacement.elevationDegrees,
            screenScale: scale,
            viewerHeightMeters: dockedPlacement.viewerHeightMeters,
            limits: .limits(for: currentEnvironment)
        )
        saveDockedPlacement()
    }

    public func setScreenDistance(_ distance: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: distance,
            elevationDegrees: dockedPlacement.elevationDegrees,
            screenScale: dockedPlacement.screenScale,
            viewerHeightMeters: dockedPlacement.viewerHeightMeters,
            limits: .limits(for: currentEnvironment)
        )
        saveDockedPlacement()
    }

    public func setScreenElevation(_ elevationDegrees: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: dockedPlacement.distanceMeters,
            elevationDegrees: elevationDegrees,
            screenScale: dockedPlacement.screenScale,
            viewerHeightMeters: dockedPlacement.viewerHeightMeters,
            limits: .limits(for: currentEnvironment)
        )
        saveDockedPlacement()
    }

    public func setViewerHeight(_ height: Double) {
        dockedPlacement = PlaybackDockedPlacement(
            distanceMeters: dockedPlacement.distanceMeters,
            elevationDegrees: dockedPlacement.elevationDegrees,
            screenScale: dockedPlacement.screenScale,
            viewerHeightMeters: height,
            limits: .limits(for: currentEnvironment)
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
                screenScale: placement.screenScale,
                viewerHeightMeters: placement.viewerHeightMeters
            )
        }
    }

    private func defaultDockedPlacement(
        for environment: SpatialSceneDomain.CinemaEnvironment
    ) -> PlaybackDockedPlacement {
        PlaybackDockedPlacement(limits: .limits(for: environment))
    }
}
