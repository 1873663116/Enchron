import SwiftUI
import Observation
import OSLog
import CoreGraphics

public struct SpatialPlaybackSurfaceObservation: Equatable {
    public static let absent = SpatialPlaybackSurfaceObservation(
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

    public let presentation: String
    public let parentName: String
    public let anchorMatched: Bool
    public let localPosition: SIMD3<Float>
    public let worldPosition: SIMD3<Float>
    public let localScale: SIMD3<Float>
    public let worldScale: SIMD3<Float>
    public let worldDistance: Float
    public let worldElevationDegrees: Float
    public let forwardToUserDot: Float
    public let playerScreenSize: SIMD2<Float>
    public let renderedSize: SIMD2<Float>
    public let renderingReady: Bool
    public let surfaceOpacity: Float
    public let contentType: String
    public let desiredImmersiveViewingMode: String
    public let actualImmersiveViewingMode: String
    public let desiredViewingMode: String
    public let actualViewingMode: String
    public let desiredSpatialVideoMode: String
    public let actualSpatialVideoMode: String
    public let settled: Bool

    public init(
        presentation: String,
        parentName: String,
        anchorMatched: Bool,
        localPosition: SIMD3<Float>,
        worldPosition: SIMD3<Float>,
        localScale: SIMD3<Float>,
        worldScale: SIMD3<Float>,
        worldDistance: Float,
        worldElevationDegrees: Float,
        forwardToUserDot: Float,
        playerScreenSize: SIMD2<Float>,
        renderedSize: SIMD2<Float>,
        renderingReady: Bool,
        surfaceOpacity: Float,
        contentType: String,
        desiredImmersiveViewingMode: String,
        actualImmersiveViewingMode: String,
        desiredViewingMode: String,
        actualViewingMode: String,
        desiredSpatialVideoMode: String,
        actualSpatialVideoMode: String,
        settled: Bool
    ) {
        self.presentation = presentation
        self.parentName = parentName
        self.anchorMatched = anchorMatched
        self.localPosition = localPosition
        self.worldPosition = worldPosition
        self.localScale = localScale
        self.worldScale = worldScale
        self.worldDistance = worldDistance
        self.worldElevationDegrees = worldElevationDegrees
        self.forwardToUserDot = forwardToUserDot
        self.playerScreenSize = playerScreenSize
        self.renderedSize = renderedSize
        self.renderingReady = renderingReady
        self.surfaceOpacity = surfaceOpacity
        self.contentType = contentType
        self.desiredImmersiveViewingMode = desiredImmersiveViewingMode
        self.actualImmersiveViewingMode = actualImmersiveViewingMode
        self.desiredViewingMode = desiredViewingMode
        self.actualViewingMode = actualViewingMode
        self.desiredSpatialVideoMode = desiredSpatialVideoMode
        self.actualSpatialVideoMode = actualSpatialVideoMode
        self.settled = settled
    }

    public var accessibilityFields: [String] {
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
public final class PlaybackSessionModel {
    public static let senseZoneVolumeID = "senseZoneVolume"

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

    public private(set) var lastObservedImmersionAmount: Double?
    public private(set) var immersiveSpaceOpeningInitialAmount: Double?
    public private(set) var immersiveSpaceStyleRevision = 0
    public private(set) var immersiveSpaceLifecycleRevision: UInt64 = 0
    private var immersionAmountBeforePanorama: Double?

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
    public private(set) var presentationTargetRendererMayBind = false
    public private(set) var presentationVisualCutoverMayBegin = false
    public private(set) var lastPresentationConversionDiagnostic: String?
    private var presentationTransitionStartedAt: Date?

    public var showControls: Bool = false {
        didSet {
            guard showControls != oldValue else { return }
            if showControls {
                scheduleControlsAutoHide()
            } else {
                cancelControlsAutoHide()
            }
        }
    }
    @ObservationIgnored public var controlsAutoHideContext: @MainActor () -> (canHide: Bool, lifecycle: String) = {
        (true, "unknown")
    }
    @ObservationIgnored public var controlsTransitionAnimation: Animation = .default
    @ObservationIgnored private var controlsAutoHideTask: Task<Void, Never>?
    public private(set) var windowTopChromeFraction: Float = 0
    private var windowControlsOrnamentHeight: CGFloat = 0
    public private(set) var windowSurfaceHeight: CGFloat = 0
    public private(set) var windowSecondaryMenuIsPresented = false
#if DEBUG
    public var showBlackoutProbeWindow: Bool = false
    public var environmentCardDismissalRequestRevision: UInt64 = 0
#endif
    public var controlsAutoHideSeconds: Int = 8
    public var isControlsFocused: Bool = false
    public var lastControlsInteractionAt: Date = .distantPast

    public var screenDepthOffset: Double {
        playbackPresentationModel.dockedPlacement.distanceMeters
    }

    public var viewerHeight: Double {
        playbackPresentationModel.dockedPlacement.viewerHeightMeters
    }

    public var screenViewAngle: Double {
        playbackPresentationModel.dockedPlacement.elevationDegrees
    }

    public var screenScale: Double {
        playbackPresentationModel.dockedPlacement.screenScale
    }

    public private(set) var spatialPlaybackSurfaceObservation =
        SpatialPlaybackSurfaceObservation.absent
    public private(set) var spatialPlaybackSurfacePreparationStage = "inactive"
    public private(set) var environmentSkyboxOpacity: Float?
    public private(set) var environmentSkyboxIsActive = false

    public var currentCinemaEnvironment: SpatialSceneDomain.CinemaEnvironment {
        playbackPresentationModel.currentEnvironment
    }

    public var defaultCardEnvironment: SpatialSceneDomain.CinemaEnvironment {
        playbackPresentationModel.defaultCardEnvironment
    }

    public func setDefaultCardEnvironment(_ environment: SpatialSceneDomain.CinemaEnvironment) {
        playbackPresentationModel.setDefaultCardEnvironment(environment)
    }

    public var dockedPlacementLimits: PlaybackDockedPlacementLimits {
        playbackPresentationModel.dockedPlacement.limits
    }

    public var currentEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect {
        playbackPresentationModel.currentEnvironmentEffect
    }

    @ObservationIgnored
    private var spatialPlatformEffectReplacementHandler: (() -> Void)?
    #if DEBUG
        @ObservationIgnored
        public var playbackSwitchPresentationRequestHandler: ((
            PlaybackPresentation,
            PlaybackPresentation
        ) -> Void)?
        @ObservationIgnored
        public var playbackSwitchPresentationSettlementHandler: ((PlaybackPresentation) -> Void)?
    #endif

    private let logger = Logger(subsystem: "app.enchron", category: "Presentation")

    public init(
        playbackPresentationModel: PlaybackPresentationModel = PlaybackPresentationModel()
    ) {
        self.playbackPresentationModel = playbackPresentationModel
    }

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
        #if DEBUG
            playbackSwitchPresentationRequestHandler?(
                transition.previousPresentation,
                transition.targetPresentation
            )
        #endif
        preparePresentationTransitionAppearance(transition)
        return transition
    }

    private func preparePresentationTransitionAppearance(
        _ transition: PlaybackPresentationTransition
    ) {
        presentationSourceRendererMayRelease = false
        presentationTargetRendererMayBind = false
        presentationVisualCutoverMayBegin = false
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
        let previousTransitionID = presentationTransition?.id
        let requested = try playbackPresentationModel.requestEnvironmentCard(
            playbackContext: playbackContext
        )
        if requested,
           let transition = presentationTransition,
           transition.id != previousTransitionID {
            preparePresentationTransitionAppearance(transition)
        }
        return requested
    }

    public func requestStoppedPlaybackCleanup(
        closesEnvironment: Bool = false,
        origin: String = #fileID,
        line: Int = #line
    ) {
        SurfaceInputProbes.record("stoppedPlaybackCleanup origin=\(origin):\(line)")
        resetPresentationTransitionAppearance()
        playbackPresentationModel.requestStoppedPlaybackCleanup(
            closesEnvironment: closesEnvironment
        )
        spatialPlatformEffectReplacementHandler?()
        logger.notice("playback stopped; spatial platform cleanup requested")
    }

    public func prepareColdPlaybackLaunch(
        for family: PresentationContentFamily
    ) {
        if let standing = presentationTransition {
            SurfaceInputProbes.record(
                "coldLaunchDuringTransition transition=\(standing.id)"
                    + " previous=\(standing.previousPresentation.rawValue)"
                    + " target=\(standing.targetPresentation.rawValue)"
                    + " family=\(family)",
                retention: .evidence
            )
        }
        resetPresentationTransitionAppearance()
        showControls = false
        playbackPresentationModel.prepareColdPlaybackLaunch(for: family)
        spatialPlatformEffectReplacementHandler?()
    }

    func recordPresentationConversionDiagnostic(_ diagnostic: String) {
        lastPresentationConversionDiagnostic = diagnostic
        SurfaceInputProbes.record("conversionFailed \(diagnostic)",
            retention: .evidence
        )
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
            #if DEBUG
                playbackSwitchPresentationSettlementHandler?(presentation)
            #endif
            resetPresentationTransitionAppearance()
            if presentation.usesMainWindow,
               environmentContext.environment != nil {
                restoreImmersionAmountAfterPanoramaIfNeeded()
            }
            logger.info("platform result committed presentation=\(presentation.rawValue, privacy: .public)")
        case .presentationRolledBack(let failure):
            resetPresentationTransitionAppearance()
            if playbackPresentation.usesMainWindow,
               environmentContext.environment != nil {
                restoreImmersionAmountAfterPanoramaIfNeeded()
            }
            logger.error("platform result rolled back transition failure=\(String(describing: failure), privacy: .public)")
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

    @discardableResult
    func allowPresentationTargetRendererBinding() -> Bool {
        guard presentationTransition != nil,
              presentationSourceRendererMayRelease else {
            return false
        }
        presentationTargetRendererMayBind = true
        return true
    }

    @discardableResult
    func beginPresentationVisualCutover() -> Bool {
        guard presentationTransition != nil,
              presentationTargetRendererMayBind else {
            return false
        }
        presentationVisualCutoverMayBegin = true
        return true
    }

    func finishPresentationVisualCutover() {
        guard presentationVisualCutoverMayBegin else { return }
        showControls = false
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
        presentationTargetRendererMayBind = false
        presentationVisualCutoverMayBegin = false
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

    public func setActiveEnvironmentEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        playbackPresentationModel.setActiveEnvironmentEffect(effect)
    }

    public func registerControlsInteraction(at date: Date = Date()) {
        lastControlsInteractionAt = date
        if showControls {
            scheduleControlsAutoHide()
        }
    }

    private func scheduleControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        guard controlsAutoHideSeconds > 0 else { return }
        let delaySeconds = controlsAutoHideSeconds
        let scheduledAtMillis = Int(Date().timeIntervalSince1970 * 1000)
        SurfaceInputProbes.record(
            "controlsVisibility event=timer-scheduled "
                + "state=\(showControls ? "shown" : "hidden") "
                + "scheduledAtMillis=\(scheduledAtMillis) "
                + "delaySeconds=\(delaySeconds) "
                + "lifecycle=\(controlsAutoHideContext().lifecycle)",
            retention: .evidence
        )
        controlsAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard let self, Task.isCancelled == false, canAutoHideControls else { return }
            let context = controlsAutoHideContext()
            guard context.canHide else { return }
            withAnimation(controlsTransitionAnimation) {
                showControls = false
            }
            SurfaceInputProbes.record(
                "controlsVisibility event=auto-hide state=hidden "
                    + "scheduledAtMillis=\(scheduledAtMillis) "
                    + "hiddenAtMillis=\(Int(Date().timeIntervalSince1970 * 1000)) "
                    + "delaySeconds=\(delaySeconds) "
                    + "lifecycle=\(context.lifecycle)",
                retention: .evidence
            )
        }
    }

    private func cancelControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        controlsAutoHideTask = nil
    }

#if DEBUG
    public var debugSurfaceTapTrace: String = "none"
#endif

    public func recordSurfaceInputProbe(
        _ fact: @autoclosure () -> String,
        retention: DebugProbeRetention = .diagnostic
    ) {
        SurfaceInputProbes.record(fact(), retention: retention)
    }

    public func toggleControlsFromPlaybackSurface(at date: Date = Date()) {
        guard presentationTransition == nil else {
            SurfaceInputProbes.record(
                "controlsVisibility event=surface-tap-ignored-during-transition",
                retention: .evidence
            )
            return
        }
        if windowSecondaryMenuIsPresented {
            windowSecondaryMenuIsPresented = false
            setControlsFocused(false, at: date)
            showControls = false
            SurfaceInputProbes.record(
                "controlsVisibility event=surface-tap-dismissed-menu-and-controls state=hidden",
                retention: .evidence
            )
            return
        }
        showControls.toggle()
        logger.info("surface tap controlsVisible=\(self.showControls)")
#if DEBUG
        debugSurfaceTapTrace = "toggled:\(showControls ? "shown" : "hidden")"
#endif
        SurfaceInputProbes.record(
            "controlsVisibility event=surface-toggle state=\(showControls ? "shown" : "hidden") interactionMillis=\(Int(date.timeIntervalSince1970 * 1000)) autoHideSeconds=\(controlsAutoHideSeconds)",
            retention: .evidence
        )
        if showControls {
            registerControlsInteraction(at: date)
        }
    }

    public func setControlsFocused(_ focused: Bool, at date: Date = Date()) {
        guard isControlsFocused != focused else { return }
        isControlsFocused = focused
        registerControlsInteraction(at: date)
    }

    public var windowChromeOcclusion: PlaybackWindowChromeOcclusion {
        PlaybackWindowChromeOcclusion(
            topFraction: windowTopChromeFraction,
            bottomFraction: showControls
                ? PlaybackWindowChromeOcclusion.bottomFraction(
                    ornamentHeight: windowControlsOrnamentHeight,
                    surfaceHeight: windowSurfaceHeight
                )
                : 0,
            secondaryMenuIsPresented: windowSecondaryMenuIsPresented
        )
    }

    public func setWindowTopChromeFraction(_ fraction: Float) {
        guard windowTopChromeFraction != fraction else { return }
        windowTopChromeFraction = fraction
    }

    public func setWindowControlsOrnamentHeight(_ height: CGFloat) {
        guard windowControlsOrnamentHeight != height else { return }
        windowControlsOrnamentHeight = height
    }

    public func setWindowSurfaceHeight(_ height: CGFloat) {
        guard windowSurfaceHeight != height else { return }
        windowSurfaceHeight = height
    }

    public func setWindowSecondaryMenuPresented(_ presented: Bool) {
        guard windowSecondaryMenuIsPresented != presented else { return }
        windowSecondaryMenuIsPresented = presented
    }

    public func systemMenuPresentationChanged(
        _ event: PlaybackMenuPresentationEvent,
        at date: Date = Date()
    ) {
        switch event {
        case .opened:
            guard windowSecondaryMenuIsPresented == false else { return }
            windowSecondaryMenuIsPresented = true
            setControlsFocused(true, at: date)
        case .closedAfterSelection:
            windowSecondaryMenuIsPresented = false
            setControlsFocused(false, at: date)
            registerControlsInteraction(at: date)
        }
        SurfaceInputProbes.record(
            "controlsVisibility event=system-menu-\(event) state=\(showControls ? "shown" : "hidden")",
            retention: .evidence
        )
    }

    public var canAutoHideControls: Bool {
        controlsAutoHideSeconds > 0 && showControls && isControlsFocused == false
    }

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
            EnvironmentSceneMapping.defaultScreenHeightMeters(
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

    public func setViewerHeight(_ height: Double) {
        playbackPresentationModel.setViewerHeight(height)
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

    func recordSpatialPlaybackSurfacePreparationStage(_ stage: String) {
        guard spatialPlaybackSurfacePreparationStage != stage else { return }
        spatialPlaybackSurfacePreparationStage = stage
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

public enum PlaybackMenuPresentationEvent: Equatable, Sendable {
    case opened
    case closedAfterSelection
}
