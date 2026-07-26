import SwiftUI
import Observation
import OSLog
import PlaybackPresentation

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
    // MARK: - Environment Card
    /// Singleton volumetric Window id hosting the Environment Card.
    public static let senseZoneVolumeID = "senseZoneVolume"

    // MARK: - Spatial Platform Execution Facts
    public let immersiveSpaceID = "ImmersiveSpace"

    public var pendingSpatialPlatformEffect: SpatialPlatformEffectRequest? {
        playbackPresentationModel.pendingSpatialPlatformEffect
    }

    public var immersiveSpaceResidency: SpatialPlatformImmersiveSpaceResidency {
        playbackPresentationModel.immersiveSpaceResidency
    }

    public var environmentCardResidency: EnvironmentCardResidency {
        playbackPresentationModel.environmentCardResidency
    }

    /// Executor-owned input to the SwiftUI immersion-style binding. Product
    /// presentation remains owned by `PlaybackPresentationModel`.
    public private(set) var platformPrefersFullImmersion = true

    // MARK: - Playback Presentation
    public let playbackPresentationModel: PlaybackPresentationModel

    public var playbackPresentation: PlaybackPresentation {
        playbackPresentationModel.presentation
    }

    public var presentationTransition: PlaybackPresentationTransition? {
        playbackPresentationModel.transition
    }

    public var environmentContext: EnvironmentContext {
        playbackPresentationModel.environmentContext
    }

    public var isTransitioningPlaybackPresentation: Bool {
        playbackPresentationModel.isTransitionExecutionOccupied
    }

    public var showControls: Bool = true
    public var controlsAutoHideSeconds: Int = 8
    public var isControlsFocused: Bool = false
    public var lastControlsInteractionAt: Date = .distantPast

    // MARK: - Screen Position State (Immersive Mode)
    public var screenDepthOffset: Double {
        playbackPresentationModel.dockedPlacement.distanceMeters
    }

    public var screenVerticalOffset: Double { 0 }

    public var screenViewAngle: Double {
        playbackPresentationModel.dockedPlacement.elevationDegrees
    }

    public var screenScale: Double {
        playbackPresentationModel.dockedPlacement.screenScale
    }

    // MARK: - Immersive Cinema State
    public var currentCinemaEnvironment: SpatialSceneDomain.CinemaEnvironment {
        playbackPresentationModel.currentEnvironment
    }

    public var currentEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect {
        playbackPresentationModel.currentEnvironmentEffect
    }

    public var automaticPanoramaEntryPending: Bool {
        playbackPresentationModel.automaticPanoramaEntryPending
    }

    @ObservationIgnored
    private var spatialPlatformEffectReplacementHandler: (() -> Void)?

    private let logger = Logger(subsystem: "app.enchron", category: "Presentation")

    public init(
        playbackPresentationModel: PlaybackPresentationModel = PlaybackPresentationModel()
    ) {
        self.playbackPresentationModel = playbackPresentationModel
    }
    
    // MARK: - Actions
    @discardableResult
    public func requestPlaybackPresentation(
        _ presentation: PlaybackPresentation,
        effect: SpatialSceneDomain.EnvironmentEffect? = nil,
        mediaSessionID: String?,
        wasPlaying: Bool
    ) throws -> PlaybackPresentationTransition {
        guard let mediaSessionID, mediaSessionID.isEmpty == false else {
            throw PlaybackPresentationTransitionError.mediaSessionRequired
        }
        let transition = try playbackPresentationModel.requestPresentation(
            presentation,
            effect: effect,
            playbackContext: SpatialPlaybackTransitionContext(
                mediaSessionID: mediaSessionID,
                wasPlaying: wasPlaying
            )
        )
        logger.info("transition requested id=\(transition.id.uuidString, privacy: .public) from=\(String(describing: transition.previousPresentation), privacy: .public) to=\(String(describing: transition.targetPresentation), privacy: .public)")
        return transition
    }

    public func activateEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) throws {
        try playbackPresentationModel.activateEnvironment(
            environment,
            effect: effect
        )
    }

    public func deactivateEnvironment() throws {
        try playbackPresentationModel.deactivateEnvironment()
    }

    public func requestEnvironmentPreview(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) throws {
        try playbackPresentationModel.requestEnvironmentPreview(
            environment: environment,
            effect: effect
        )
    }

    public func requestEnvironmentPreviewDismissal() throws {
        try playbackPresentationModel.requestEnvironmentPreviewDismissal()
    }

    @discardableResult
    public func requestEnvironmentCard(
        mediaSessionID: String? = nil,
        wasPlaying: Bool = false
    ) throws -> Bool {
        let playbackContext = mediaSessionID.map {
            SpatialPlaybackTransitionContext(
                mediaSessionID: $0,
                wasPlaying: wasPlaying
            )
        }
        return try playbackPresentationModel.requestEnvironmentCard(
            playbackContext: playbackContext
        )
    }

    public func requestStoppedPlaybackCleanup() {
        playbackPresentationModel.requestStoppedPlaybackCleanup()
        spatialPlatformEffectReplacementHandler?()
        logger.notice("playback stopped; spatial platform cleanup requested")
    }

    @discardableResult
    public func claimSpatialPlatformEffect(
        _ requestID: UUID,
        executionID: UUID
    ) -> Bool {
        playbackPresentationModel.claimSpatialPlatformEffect(
            requestID,
            executionID: executionID
        )
    }

    public func isSpatialPlatformEffectCurrent(
        _ requestID: UUID,
        executionID: UUID
    ) -> Bool {
        playbackPresentationModel.isSpatialPlatformEffectCurrent(
            requestID,
            executionID: executionID
        )
    }

    func setSpatialPlatformEffectReplacementHandler(
        _ handler: @escaping () -> Void
    ) {
        spatialPlatformEffectReplacementHandler = handler
    }

    @discardableResult
    public func receiveSpatialPlatformResult(
        _ event: SpatialPlatformResultEvent
    ) -> SpatialPlatformEffectResolution {
        let resolution = playbackPresentationModel.receiveSpatialPlatformResult(event)
        switch resolution {
        case .presentationCommitted(let presentation):
            logger.info("platform result committed presentation=\(presentation.rawValue, privacy: .public)")
        case .presentationRolledBack(let failure):
            logger.error("platform result rolled back transition failure=\(String(describing: failure), privacy: .public)")
        case .spatialRecoveryRequested(let presentation):
            logger.notice("unexpected immersive dismissal; recovery requested presentation=\(presentation.rawValue, privacy: .public)")
        case .spatialRecoveryCompleted(let presentation):
            logger.notice("spatial recovery completed presentation=\(presentation.rawValue, privacy: .public)")
        case .spatialRecoveryFailed(let failure):
            logger.error("spatial recovery failed; settled in Window failure=\(String(describing: failure), privacy: .public)")
        case .playbackTransportFailureRecorded:
            logger.error("playback transport failed after platform effect settlement")
        case .ignored:
            logger.info("stale or duplicate platform result ignored")
        case .platformFactRecorded, .effectCompleted:
            break
        }
        return resolution
    }

    public func setPlatformPrefersFullImmersion(_ full: Bool) {
        platformPrefersFullImmersion = full
    }

    public func configureDefaultEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment
    ) {
        playbackPresentationModel.configureDefaultEnvironment(environment)
    }

    public func setActiveEnvironmentEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        playbackPresentationModel.setActiveEnvironmentEffect(effect)
    }

    public func setAutomaticPanoramaEntryPending(_ pending: Bool) {
        playbackPresentationModel.setAutomaticPanoramaEntryPending(pending)
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
        await playbackPresentationModel.loadDockedPlacement()
    }

    public func saveScreenPosition() {
        playbackPresentationModel.saveDockedPlacement()
    }

    public func setScreenScale(_ scale: Double) {
        playbackPresentationModel.setScreenScale(scale)
    }

    public func resetScreenScale() {
        playbackPresentationModel.setScreenScale(
            EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: currentCinemaEnvironment.rawValue
            )
        )
    }

    public func setScreenDistance(_ distance: Double) {
        playbackPresentationModel.setScreenDistance(distance)
    }

    public func setScreenElevation(_ degrees: Double) {
        playbackPresentationModel.setScreenElevation(degrees)
    }

    public func resetDockedPlacement() {
        playbackPresentationModel.resetDockedPlacement()
    }

}
