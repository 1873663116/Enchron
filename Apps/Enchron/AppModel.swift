import SwiftUI
import Observation
import OSLog
import PlaybackPresentation

struct SpatialPlaybackSurfaceObservation: Equatable {
    static let absent = SpatialPlaybackSurfaceObservation(
        presentation: "none",
        parentName: "none",
        anchorMatched: false,
        localPosition: .zero,
        worldPosition: .zero,
        localScale: .zero,
        worldScale: .zero,
        worldDistance: 0,
        worldElevationDegrees: 0,
        forwardToUserDot: 0,
        playerScreenSize: .zero,
        renderedSize: .zero,
        renderingReady: false,
        surfaceOpacity: 0,
        contentType: "none",
        desiredImmersiveViewingMode: "none",
        actualImmersiveViewingMode: "none",
        desiredViewingMode: "none",
        actualViewingMode: "none",
        desiredSpatialVideoMode: "none",
        actualSpatialVideoMode: "none",
        settled: false
    )

    let presentation: String
    let parentName: String
    let anchorMatched: Bool
    let localPosition: SIMD3<Float>
    let worldPosition: SIMD3<Float>
    let localScale: SIMD3<Float>
    let worldScale: SIMD3<Float>
    let worldDistance: Float
    let worldElevationDegrees: Float
    let forwardToUserDot: Float
    let playerScreenSize: SIMD2<Float>
    let renderedSize: SIMD2<Float>
    let renderingReady: Bool
    let surfaceOpacity: Float
    let contentType: String
    let desiredImmersiveViewingMode: String
    let actualImmersiveViewingMode: String
    let desiredViewingMode: String
    let actualViewingMode: String
    let desiredSpatialVideoMode: String
    let actualSpatialVideoMode: String
    let settled: Bool

    var accessibilityFields: [String] {
        [
            "surfacePresentation=\(presentation)",
            "surfaceParent=\(parentName.replacingOccurrences(of: ";", with: ","))",
            "surfaceAnchorMatched=\(anchorMatched)",
            "surfaceLocalX=\(formatted(localPosition.x))",
            "surfaceLocalY=\(formatted(localPosition.y))",
            "surfaceLocalZ=\(formatted(localPosition.z))",
            "surfaceWorldX=\(formatted(worldPosition.x))",
            "surfaceWorldY=\(formatted(worldPosition.y))",
            "surfaceWorldZ=\(formatted(worldPosition.z))",
            "surfaceLocalScaleX=\(formatted(localScale.x))",
            "surfaceLocalScaleY=\(formatted(localScale.y))",
            "surfaceLocalScaleZ=\(formatted(localScale.z))",
            "surfaceWorldScaleX=\(formatted(worldScale.x))",
            "surfaceWorldScaleY=\(formatted(worldScale.y))",
            "surfaceWorldScaleZ=\(formatted(worldScale.z))",
            "surfaceWorldDistance=\(formatted(worldDistance))",
            "surfaceWorldElevation=\(formatted(worldElevationDegrees))",
            "surfaceForwardToUserDot=\(formatted(forwardToUserDot))",
            "surfacePlayerWidth=\(formatted(playerScreenSize.x))",
            "surfacePlayerHeight=\(formatted(playerScreenSize.y))",
            "surfaceRenderedWidth=\(formatted(renderedSize.x))",
            "surfaceRenderedHeight=\(formatted(renderedSize.y))",
            "surfaceRenderingReady=\(renderingReady)",
            "surfaceOpacity=\(formatted(surfaceOpacity))",
            "surfaceContentType=\(sanitized(contentType))",
            "surfaceDesiredImmersiveMode=\(sanitized(desiredImmersiveViewingMode))",
            "surfaceActualImmersiveMode=\(sanitized(actualImmersiveViewingMode))",
            "surfaceDesiredViewingMode=\(sanitized(desiredViewingMode))",
            "surfaceActualViewingMode=\(sanitized(actualViewingMode))",
            "surfaceDesiredSpatialVideoMode=\(sanitized(desiredSpatialVideoMode))",
            "surfaceActualSpatialVideoMode=\(sanitized(actualSpatialVideoMode))",
            "surfaceSettled=\(settled)"
        ]
    }

    private func formatted(_ value: Float) -> String {
        String(format: "%.4f", value)
    }

    private func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: ";", with: ",")
    }
}

@MainActor
@Observable
public final class AppModel {
    // MARK: - Navigation State
    public enum NavigationTab: String, CaseIterable {
        case files, settings, environment

        /// Files/Settings render system TabView content; Environment opens a separate
        /// volume and does not park the main window on an empty tab (LNCH-03).
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

    /// Process-local observation used to preserve the system's progressive
    /// immersion amount across Immersive Space open cycles.
    public private(set) var lastObservedImmersionAmount: Double?
    public private(set) var immersiveSpaceOpeningInitialAmount: Double?
    public private(set) var immersiveSpaceStyleRevision = 0
    public private(set) var immersiveSpaceLifecycleRevision: UInt64 = 0
    private var immersionAmountBeforePanorama: Double?

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

    public var panoramaReturnEnvironmentContext: EnvironmentContext? {
        playbackPresentationModel.panoramaReturnEnvironmentContext
    }

    public var isTransitioningPlaybackPresentation: Bool {
        playbackPresentationModel.isTransitionExecutionOccupied
    }

    public private(set) var presentationSourceRendererMayRelease = false
    private var windowPortalToProgressiveChangeConfirmedTransitionID: UUID?
    private var presentationTransitionStartedAt: Date?

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

    private(set) var spatialPlaybackSurfaceObservation =
        SpatialPlaybackSurfaceObservation.absent
    private(set) var environmentSkyboxOpacity: Float?
    private(set) var environmentSkyboxIsActive = false

    // MARK: - Immersive Cinema State
    public var currentCinemaEnvironment: SpatialSceneDomain.CinemaEnvironment {
        playbackPresentationModel.currentEnvironment
    }

    public var defaultScenicEnvironment: SpatialSceneDomain.CinemaEnvironment {
        playbackPresentationModel.defaultEnvironment
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
        environment: SpatialSceneDomain.CinemaEnvironment? = nil,
        effect: SpatialSceneDomain.EnvironmentEffect? = nil,
        mediaSessionID: String?,
        wasPlaying: Bool
    ) throws -> PlaybackPresentationTransition {
        guard let mediaSessionID, mediaSessionID.isEmpty == false else {
            throw PlaybackPresentationTransitionError.mediaSessionRequired
        }
        let transition = try playbackPresentationModel.requestPresentation(
            presentation,
            environment: environment,
            effect: effect,
            playbackContext: SpatialPlaybackTransitionContext(
                mediaSessionID: mediaSessionID,
                wasPlaying: wasPlaying
            )
        )
        presentationSourceRendererMayRelease = false
        windowPortalToProgressiveChangeConfirmedTransitionID = nil
        presentationTransitionStartedAt = Date()
        if transition.targetPresentation == .panorama,
           transition.previousEnvironment.environment != nil,
           transition.targetEnvironment == .none {
            immersionAmountBeforePanorama =
                SpatialImmersiveSpacePolicy.normalized(lastObservedImmersionAmount)
        }
        let previousPresentation = String(describing: transition.previousPresentation)
        let targetPresentation = String(describing: transition.targetPresentation)
        logger.info(
            """
            transition requested id=\(transition.id.uuidString, privacy: .public) \
            from=\(previousPresentation, privacy: .public) \
            to=\(targetPresentation, privacy: .public)
            """
        )
        return transition
    }

    public func activateEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?
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
        effect: SpatialSceneDomain.EnvironmentEffect?
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
        resetPresentationTransitionAppearance()
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
        switch event {
        case .immersiveSpaceAppeared, .immersiveSpaceDisappeared:
            immersiveSpaceLifecycleRevision &+= 1
        default:
            break
        }
        let resolution = playbackPresentationModel.receiveSpatialPlatformResult(event)
        switch resolution {
        case .presentationCommitted(let presentation):
            resetPresentationTransitionAppearance()
            if presentation == .window,
               environmentContext.environment != nil {
                restoreImmersionAmountAfterPanoramaIfNeeded()
            }
            logger.info("platform result committed presentation=\(presentation.rawValue, privacy: .public)")
        case .presentationRolledBack(let failure):
            resetPresentationTransitionAppearance()
            if playbackPresentation == .window,
               environmentContext.environment != nil {
                restoreImmersionAmountAfterPanoramaIfNeeded()
            }
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

    @discardableResult
    func allowPresentationSourceRendererRelease() -> Bool {
        guard presentationTransition != nil else { return false }
        presentationSourceRendererMayRelease = true
        return true
    }

    func recordWindowPortalToProgressiveChange(for transitionID: UUID) {
        guard let transition = presentationTransition,
              transition.id == transitionID,
              transition.requiresWindowPortalToProgressiveChange else {
            return
        }
        windowPortalToProgressiveChangeConfirmedTransitionID = transitionID
    }

    func windowPortalToProgressiveChangeIsConfirmed(
        for transitionID: UUID
    ) -> Bool {
        windowPortalToProgressiveChangeConfirmedTransitionID == transitionID
    }

    var windowPortalToProgressiveChangeIsConfirmed: Bool {
        guard let transition = presentationTransition else { return false }
        return windowPortalToProgressiveChangeIsConfirmed(for: transition.id)
    }

    func presentationTransitionRemainingTime(
        until elapsedTime: TimeInterval,
        now: Date = Date()
    ) -> TimeInterval? {
        guard let presentationTransitionStartedAt else { return nil }
        return max(
            0,
            elapsedTime - now.timeIntervalSince(presentationTransitionStartedAt)
        )
    }

    private func resetPresentationTransitionAppearance() {
        presentationSourceRendererMayRelease = false
        windowPortalToProgressiveChangeConfirmedTransitionID = nil
        presentationTransitionStartedAt = nil
    }

    public func recordImmersionAmount(_ amount: Double?) {
        guard let normalized = SpatialImmersiveSpacePolicy.normalized(amount) else {
            return
        }
        lastObservedImmersionAmount = normalized
    }

    public func prepareImmersiveSpaceOpening(initialAmount: Double?) {
        immersiveSpaceOpeningInitialAmount =
            SpatialImmersiveSpacePolicy.normalized(initialAmount)
        immersiveSpaceStyleRevision &+= 1
    }

    private func restoreImmersionAmountAfterPanoramaIfNeeded() {
        guard let immersionAmountBeforePanorama else { return }
        self.immersionAmountBeforePanorama = nil
        prepareImmersiveSpaceOpening(initialAmount: immersionAmountBeforePanorama)
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

    /// Last surface-tap decision, exposed through Window control-plane value for XCUI.
    public var debugSurfaceTapTrace: String = "none"

    public func toggleControlsFromPlaybackSurface(at date: Date = Date()) {
        showControls.toggle()
        logger.info("surface tap controlsVisible=\(self.showControls)")
        debugSurfaceTapTrace = "toggled:\(showControls ? "shown" : "hidden")"
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

    func recordSpatialPlaybackSurfaceObservation(
        _ observation: SpatialPlaybackSurfaceObservation
    ) {
        guard spatialPlaybackSurfaceObservation != observation else { return }
        spatialPlaybackSurfaceObservation = observation
    }

    func clearSpatialPlaybackSurfaceObservation() {
        guard spatialPlaybackSurfaceObservation != .absent else { return }
        spatialPlaybackSurfaceObservation = .absent
    }

    func recordEnvironmentSceneEffect(opacity: Float) {
        guard environmentSkyboxOpacity != opacity else { return }
        environmentSkyboxOpacity = opacity
    }

    func recordEnvironmentSkyboxIsActive(_ isActive: Bool) {
        guard environmentSkyboxIsActive != isActive else { return }
        environmentSkyboxIsActive = isActive
    }

    func clearEnvironmentSceneEffectObservation() {
        guard environmentSkyboxOpacity != nil || environmentSkyboxIsActive else { return }
        environmentSkyboxOpacity = nil
        environmentSkyboxIsActive = false
    }

}
