import SwiftUI
import Observation
import OSLog

@MainActor
@Observable
public final class AppModel {
    // MARK: - Navigation State
    public enum NavigationTab: String, CaseIterable {
        case files, settings, environment

        /// Files/Settings render content in the main window; Environment opens a
        /// separate destination (volume) and does not park the main window (LNCH-03).
        var isContentDestination: Bool {
            self != .environment
        }
    }
    public var selectedTab: NavigationTab = .files
    // MARK: - SenseZone Volume (Environments destination)
    /// Volumetric WindowGroup id hosting the polished EnvironmentCardCarousel.
    public static let senseZoneVolumeID = "senseZoneVolume"
    /// Tab to restore in the main window when the SenseZone volume closes (ENV-14).
    public var environmentReturnTab: NavigationTab = .files
    /// Guards against re-entrant volume open/close during a transition (ENV-15).
    public var isEnvironmentTransitionInFlight: Bool = false

    // MARK: - Immersive Space State
    public let immersiveSpaceID = "ImmersiveSpace"

    public enum ImmersiveSpaceState: Equatable, Sendable {
        case closed
        case inTransition
        case open
    }
    public var immersiveSpaceState: ImmersiveSpaceState = .closed

    /// Pending immersive space action requested by sub-views.
    /// MainView observes this and executes the actual open/dismiss call,
    /// then resets it to nil. This ensures a single canonical entry point.
    public enum ImmersiveSpaceRequest {
        case open
        case dismiss
    }
    public var immersiveSpaceRequest: ImmersiveSpaceRequest? = nil

    /// True while a playback-presentation transition is in progress (immersive space
    /// opening or closing). Gates playerControls window open/close and
    /// prevents concurrent menu operations.
    public var isTransitioningPlaybackPresentation: Bool = false
    
    // MARK: - Playback Presentation
    public var playbackPresentationState = PlaybackPresentationState()
    public var playbackPresentation: PlaybackPresentation {
        playbackPresentationState.presented
    }
    public var presentationTransition: PlaybackPresentationTransition? {
        playbackPresentationState.transition
    }
    public var environmentContext: EnvironmentContext {
        playbackPresentationState.environment
    }
    public var showControls: Bool = true
    public var controlsAutoHideSeconds: Int = 8
    public var isControlsFocused: Bool = false
    public var lastControlsInteractionAt: Date = .distantPast

    // MARK: - Screen Position State (Immersive Mode)
    public var screenDepthOffset: Double = 0.0
    public var screenVerticalOffset: Double = 0.0
    public var screenViewAngle: Double = 0.0
    public var screenScale: Double = 1.3

    // MARK: - Immersive Cinema State
    public var currentCinemaEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre
    public var isFullImmersion: Bool = true

    /// True while the immersive space is presenting the RCP `world` for
    /// environment-expand browsing (ENV-18) rather than video playback. Drives
    /// `ImmersiveSpaceView` to load the `world` even though presentation stays
    /// `.window`, and selects mixed immersion so the SenseZone volume stays open.
    public var isEnvironmentImmersiveActive: Bool = false

    private let screenPositionStore: ScreenPositionStoring
    private let logger = Logger(subsystem: "app.enchron", category: "Presentation")

    public init(screenPositionStore: ScreenPositionStoring = ScreenPositionStore()) {
        self.screenPositionStore = screenPositionStore
    }
    
    // MARK: - Actions
    @discardableResult
    public func requestPlaybackPresentation(
        _ presentation: PlaybackPresentation,
        environment: SpatialSceneDomain.CinemaEnvironment? = nil
    ) throws -> PlaybackPresentationTransition {
        let transition = try playbackPresentationState.begin(
            presentation,
            environment: environment,
            defaultEnvironment: currentCinemaEnvironment
        )
        logger.info("transition requested id=\(transition.id.uuidString, privacy: .public) from=\(String(describing: transition.previousPresentation), privacy: .public) to=\(String(describing: transition.targetPresentation), privacy: .public)")
        return transition
    }

    public func commitPlaybackPresentation(_ transitionID: UUID) throws {
        try playbackPresentationState.commit(transitionID)
        logger.info("transition committed id=\(transitionID.uuidString, privacy: .public)")
        if let environment = playbackPresentationState.environment.environment {
            currentCinemaEnvironment = environment
        }
    }

    public func rollbackPlaybackPresentation(_ transitionID: UUID) {
        playbackPresentationState.rollback(transitionID)
        logger.error("transition rolled back id=\(transitionID.uuidString, privacy: .public)")
    }

    public func updateEnvironmentContext(_ context: EnvironmentContext) throws {
        try playbackPresentationState.setEnvironment(context)
        if let environment = context.environment {
            currentCinemaEnvironment = environment
        }
    }

    public func resetPlaybackPresentationForStoppedPlayback() {
        playbackPresentationState.resetForPlaybackStop()
        isTransitioningPlaybackPresentation = false
        logger.notice("playback stopped; presentation normalized to window")
    }

    public func registerControlsInteraction(at date: Date = Date()) {
        lastControlsInteractionAt = date
    }

    public func toggleControlsFromPlaybackSurface(at date: Date = Date()) {
        let elapsed = date.timeIntervalSince(lastControlsInteractionAt)
        guard elapsed > 0.5 else {
            logger.info("surface tap ignored during playback transition")
            return
        }
        showControls.toggle()
        logger.info("surface tap controlsVisible=\(self.showControls)")
        if showControls {
            registerControlsInteraction(at: date)
        }
    }

    public func setControlsFocused(_ focused: Bool, at date: Date = Date()) {
        isControlsFocused = focused
        registerControlsInteraction(at: date)
    }

    public var canAutoHideControls: Bool {
        controlsAutoHideSeconds > 0 && showControls && isControlsFocused == false
    }

    // MARK: - Screen Position Persistence

    public func loadScreenPosition() async {
        let envID = currentCinemaEnvironment.rawValue
        if let saved = await screenPositionStore.loadPosition(for: envID) {
            screenDepthOffset = saved.depthOffsetMeters
            screenVerticalOffset = saved.verticalOffsetMeters
            screenViewAngle = saved.viewAngleDegrees
            screenScale = saved.screenScale
        } else {
            // Reset to defaults when no saved position exists for this environment
            screenDepthOffset = 0.0
            screenVerticalOffset = 0.0
            screenViewAngle = 0.0
            screenScale = EnvironmentSceneMapping.defaultScreenScale(forEnvironmentID: envID)
        }
    }

    public func saveScreenPosition() {
        let envID = currentCinemaEnvironment.rawValue
        let store = screenPositionStore
        let depthOffset = screenDepthOffset
        let verticalOffset = screenVerticalOffset
        let viewAngle = screenViewAngle
        let scale = screenScale
        Task.detached(priority: .utility) {
            await store.savePosition(
                for: envID,
                depthOffsetMeters: depthOffset,
                verticalOffsetMeters: verticalOffset,
                angleDegrees: viewAngle,
                screenScale: scale
            )
        }
    }

    public func setScreenScale(_ scale: Double) {
        screenScale = min(
            max(scale, PlaybackScreenSize.scaleRange.lowerBound),
            PlaybackScreenSize.scaleRange.upperBound
        )
        saveScreenPosition()
    }

    public func resetScreenScale() {
        setScreenScale(
            EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: currentCinemaEnvironment.rawValue
            )
        )
    }

    /// Request to open the immersive space via the unified MainView handler.
    public func requestImmersiveSpace() {
        guard immersiveSpaceState == .closed else { return }
        immersiveSpaceRequest = .open
    }

    /// Request to dismiss the immersive space via the unified MainView handler.
    public func requestDismissImmersiveSpace() {
        guard immersiveSpaceState == .open else { return }
        immersiveSpaceRequest = .dismiss
    }

    public func switchEnvironment(to environment: SpatialSceneDomain.CinemaEnvironment) async {
        guard environment != currentCinemaEnvironment else { return }
        saveScreenPosition()
        currentCinemaEnvironment = environment
        await loadScreenPosition()
    }
}
