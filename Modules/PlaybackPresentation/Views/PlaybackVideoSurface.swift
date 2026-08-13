import AVFoundation
import RealityKit
import OSLog
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

private let playbackVideoSurfaceLogger = Logger(
    subsystem: "com.xiongzhipeng.XTransferPlayer",
    category: "PlaybackVideoSurface"
)

@MainActor
private final class PlaybackVideoComponentObservation {
    private var entityID: ObjectIdentifier?
    private var contentTypeSessionID: String?
    private var subscriptions: [EventSubscription] = []
    private var lastLayoutSignature: String?
    private var lastStateSignature: String?
    // One slot per log kind. Sharing a slot between the per-frame surface facts
    // and the attach probe meant neither ever repeated its own last value, so
    // the attach probe fired every frame and flooded the probe file.
    private var lastAttachSignature: String?
    private var lastPhaseSignature: String?
    private let modeRequestRetry = PlaybackModeRequestRetry()

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        in content: Content,
        contentTypeSessionID: String?,
        onChange: @escaping @MainActor (String) -> Void,
        onContentTypeDidChange: @escaping @MainActor (
            String,
            String
        ) -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard entityID != nextEntityID
                || self.contentTypeSessionID != contentTypeSessionID else {
            return
        }
        cancelSubscriptions()
        entityID = nextEntityID
        self.contentTypeSessionID = contentTypeSessionID
        subscriptions = [
            content.subscribe(to: VideoPlayerEvents.VideoSizeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange("videoSizeDidChange") }
            },
            content.subscribe(to: VideoPlayerEvents.ViewingModeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange("viewingModeDidChange") }
            },
            content.subscribe(
                to: VideoPlayerEvents.ImmersiveViewingModeWillTransition.self,
                on: entity
            ) { _ in
                Task { @MainActor in onChange("immersiveViewingModeWillTransition") }
            },
            content.subscribe(
                to: VideoPlayerEvents.ImmersiveViewingModeDidChange.self,
                on: entity
            ) { _ in
                Task { @MainActor in
                    onChange("immersiveViewingModeDidChange")
                }
            },
            content.subscribe(
                to: VideoPlayerEvents.ImmersiveViewingModeDidTransition.self,
                on: entity
            ) { _ in
                Task { @MainActor in onChange("immersiveViewingModeDidTransition") }
            },
            content.subscribe(to: VideoPlayerEvents.RenderingStatusDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange("renderingStatusDidChange") }
            }
        ]
        if let contentTypeSessionID {
            // Apple's ContentTypeDidChange event doesn't identify its Entity.
            // Keep one subscription for the session so a format change never
            // depends on RealityKit replaying the event after resubscription.
            subscriptions.append(
                content.subscribe(to: VideoPlayerEvents.ContentTypeDidChange.self) { event in
                    let contentType = String(describing: event.contentType)
                    Task { @MainActor in
                        onContentTypeDidChange(contentType, contentTypeSessionID)
                        onChange("contentTypeDidChange")
                    }
                }
            )
        }
    }

    func cancel() {
        cancelSubscriptions()
        entityID = nil
        contentTypeSessionID = nil
        modeRequestRetry.reset()
    }

    private func cancelSubscriptions() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }

    func shouldLogLayout(_ signature: String) -> Bool {
        guard lastLayoutSignature != signature else { return false }
        lastLayoutSignature = signature
        return true
    }

    func shouldLogState(_ signature: String) -> Bool {
        guard lastStateSignature != signature else { return false }
        lastStateSignature = signature
        return true
    }

    func shouldLogAttach(_ signature: String) -> Bool {
        guard lastAttachSignature != signature else { return false }
        lastAttachSignature = signature
        return true
    }

    func shouldLogPhase(_ signature: String) -> Bool {
        guard lastPhaseSignature != signature else { return false }
        lastPhaseSignature = signature
        return true
    }

    func modeRecoveryAction(
        to entity: Entity,
        presentation: PlaybackPresentation,
        component: VideoPlayerComponent,
        requiresImmersiveViewingModeSettlement: Bool
    ) -> PlaybackModeRecoveryAction {
        modeRequestRetry.recoveryAction(
            entity: entity,
            presentation: presentation,
            desiredImmersiveViewingMode: String(
                describing: component.desiredImmersiveViewingMode
            ),
            actualImmersiveViewingMode: component.immersiveViewingMode.map {
                String(describing: $0)
            },
            desiredSpatialVideoMode: String(
                describing: component.desiredSpatialVideoMode
            ),
            actualSpatialVideoMode: String(describing: component.spatialVideoMode),
            requiresImmersiveViewingModeSettlement:
                requiresImmersiveViewingModeSettlement
        )
    }
}

struct PlaybackVideoSurface: View {
    private static let subtitleControlSafeAreaFraction: Float = 0.32

    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore

    let presentation: PlaybackPresentation
    let isActive: Bool

    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var realityViewUpdateScheduler = PlaybackRealityViewUpdateScheduler()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var surfaceAccessibilityActivation =
        PlaybackSurfaceAccessibilityActivationObservation()
    @State private var rendererTargetObservation =
        PlaybackVideoRendererTargetObservation()
    @State private var componentObservation = PlaybackVideoComponentObservation()
    @State private var componentRevision = 0
    @State private var surfaceRefreshTick = 0

    private var videoEntity: Entity {
        playbackVideoEntityStore.hostedEntity(
            for: presentation,
            during: appModel.presentationTransition
        )
    }

    private var realityKitContentTypeScope: PlaybackRealityKitContentTypeScope? {
        PlaybackRealityKitContentTypeScope(runtime: playbackRuntime)
    }
    @ViewBuilder
    var body: some View {
        ZStack {
            visionSurface

            if let activeSubtitleText {
                Text(activeSubtitleText)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Subtitles")
                    .accessibilityValue(activeSubtitleText)
                    .accessibilityIdentifier("PlayerUI-active-subtitles")
            }
        }
    }

    private var visionSurface: some View {
        let realityViewDepth = WindowPlaybackSurfaceGeometry.realityViewDepth(
            for: presentation
        )
        return GeometryReader3D { geometry in
            RealityView { content in
                scheduleVisionSurfaceUpdate(content, proxy: geometry)
            } update: { content in
                scheduleVisionSurfaceUpdate(content, proxy: geometry)
            }
            .frame(depth: realityViewDepth)
        }
        .frame(depth: realityViewDepth)
        .task(id: surfaceReadinessKey) {
            await retrySurfaceAttachment()
        }
        .onChange(of: playbackRuntime.videoComponentRevision) {
            surfaceRefreshTick &+= 1
        }
        .onChange(of: realityKitContentTypeScope) { _, scope in
            playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(scope)
            surfaceRefreshTick &+= 1
        }
        .onChange(of: appModel.presentationTransition?.id) {
            componentRevision &+= 1
        }
        .onDisappear {
            realityViewUpdateScheduler.cancel()
            releaseSurface()
        }
    }

    private func scheduleVisionSurfaceUpdate(
        _ content: RealityViewContent,
        proxy: GeometryProxy3D
    ) {
        let revision = componentRevision &+ surfaceRefreshTick
        realityViewUpdateScheduler.schedule {
            updateVisionSurface(content, proxy: proxy, revision: revision)
        }
    }
    private func toggleControlsFromAccessibilityActivation() {
        withAnimation(.easeInOut(duration: 0.25)) {
            PlaybackSurfaceInputAction.perform(
                .accessibilityActivate,
                appModel: appModel
            )
        }
    }

    private var surfaceReadinessKey: String {
        let rendererID = playbackRuntime.renderer.map {
            String(describing: ObjectIdentifier($0))
        } ?? "none"
        let contentTypeScope = realityKitContentTypeScope
        return [
            presentation.rawValue,
            isActive ? "active" : "inactive",
            playbackRuntime.hasActivePlaybackRequest ? "requestActive" : "requestNone",
            playbackRuntime.productLifecycle.rawValue,
            playbackRuntime.mediaFormatIsKnown ? "formatReady" : "formatPending",
            rendererID,
            contentTypeScope?.sessionID ?? "sessionNone",
            playbackRuntime.activeMediaFormatProvenance.rawValue,
            playbackRuntime.sourceVideoContentKind.rawValue,
            playbackRuntime.effectiveProjectionType.rawValue,
            String(playbackRuntime.effectiveHorizontalFieldOfViewDegrees),
            playbackRuntime.effectiveStereoLayout.rawValue,
            playbackRuntime.effectiveVideoFormatRevision.map(String.init)
                ?? "formatRevisionNone"
        ].joined(separator: "|")
    }

    @MainActor
    private func retrySurfaceAttachment() async {
        while surfaceAttachmentCanStillSettle {
            guard Task.isCancelled == false else { return }
            if playbackRuntime.attachedPresentation == presentation,
               playbackRuntime.rendererConsumerEntityID == entityID,
               videoEntity.isActive,
               presentationPhase == .settled {
                return
            }
            surfaceRefreshTick &+= 1
            surfaceActivation.requestRetry()
            try? await Task.sleep(for: PlaybackSurfaceActivation.retryIntervalForView)
        }
    }

    /// Slow first frames remain eligible to attach for the lifetime of the
    /// active media request. Only product state, not elapsed wall-clock time,
    /// can prove that this RealityView will never settle.
    private var surfaceAttachmentCanStillSettle: Bool {
        guard isActive, playbackRuntime.hasActivePlaybackRequest else {
            return false
        }
        switch playbackRuntime.productLifecycle {
        case .loading, .ready, .playing, .paused, .ended:
            return true
        case .idle, .failed:
            return false
        }
    }

    @MainActor
    private func prepareSurface<Content: RealityViewContentProtocol>(
        in content: Content,
        revision: Int
    ) -> Bool {
        _ = revision
        let contentTypeScope = realityKitContentTypeScope
        playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(
            contentTypeScope
        )
        logSurfaceFacts(reason: "prepareCheck")
        guard isActive else {
            if preservesDepartingSurfaceForFade {
                releaseRendererOwnershipWhileKeepingVisibleSurface()
            } else {
                releaseSurface(from: content)
            }
            return false
        }
        guard playbackRuntime.mediaFormatIsKnown,
              let renderer = playbackRuntime.renderer else {
            releaseSurface(from: content)
            return false
        }
        if let rendererConsumerPresentation = playbackRuntime.rendererConsumerPresentation,
           rendererConsumerPresentation.usesImmersiveSpace {
            return false
        }

        let videoComponentRevision = playbackRuntime.videoComponentRevision
        _ = playbackVideoEntityStore.entity(
            for: renderer,
            presentation: presentation,
            videoComponentRevision: videoComponentRevision
        )

        // A technical-session replacement inside one presentation has no Scene
        // disappearance to retire the previous video entity. Leaving it parented
        // keeps its VideoPlayerComponent feeding the last frame above the new
        // surface, and every retained renderer keeps its decode pipeline alive
        // in mediaplaybackd until the daemon hits its memory ceiling.
        if appModel.presentationTransition == nil,
           let departingEntity = playbackVideoEntityStore.departingEntity,
           departingEntity !== videoEntity {
            content.remove(departingEntity)
            playbackVideoEntityStore.releaseDepartingEntity()
        }

        do {
            try playbackRuntime.claimRendererConsumer(
                presentation: presentation,
                entityID: entityID
            )
        } catch PlaybackRuntime.RuntimeError.rendererTransferPending {
            return false
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
            releaseSurface(from: content)
            return false
        }

        let needsInsertion = content.entities.contains(where: { $0 === videoEntity }) == false
        videoEntity.name = "EnchronVideo.\(presentation)"
        rendererTargetObservation.observe(
            videoEntity,
            videoComponentRevision: videoComponentRevision,
            in: content
        ) {
            playbackRuntime.videoRendererTargetDidBind(
                revision: videoComponentRevision,
                entityID: entityID
            )
        }
        componentObservation.observe(
            videoEntity,
            in: content,
            contentTypeSessionID: contentTypeScope?.technicalSessionID,
            onChange: { reason in
                logComponentState(reason: reason)
                componentRevision &+= 1
            },
            onContentTypeDidChange: { contentType, eventSessionID in
                playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(
                    realityKitContentTypeScope
                )
                playbackVideoEntityStore.recordRealityKitContentType(
                    contentType,
                    forTechnicalSessionID: eventSessionID
                )
            }
        )
        surfaceActivation.observe(videoEntity, in: content) {
            attachSurfaceIfReady()
        }
        if needsInsertion {
            content.add(videoEntity)
        }
        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: presentation,
            requestsSpatialVideoMode: playbackRuntime.requestsSpatialVideoMode,
            requestsProgressiveImmersiveViewingMode: false
        )
        let videoEntityOpacity = PlaybackPresentationTransitionAppearance.windowVideoEntityOpacity(
            for: presentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition,
            visualCutoverMayBegin: appModel.presentationVisualCutoverMayBegin
        )
        PlaybackRealityPresenter.setOpacity(
            of: videoEntity,
            to: Float(videoEntityOpacity),
            animated: videoEntity.components[OpacityComponent.self] != nil
        )
        surfaceAccessibilityActivation.observe(videoEntity, in: content) {
            toggleControlsFromAccessibilityActivation()
        }
        subtitleSurface.update(
            on: videoEntity,
            presentation: presentation,
            screenSize: component?.playerScreenSize ?? .zero,
            reservedBottomFraction: appModel.showControls
                ? Self.subtitleControlSafeAreaFraction
                : 0,
            frame: playbackRuntime.activeSubtitleFrame
        )
        if needsInsertion {
            logComponentState(reason: "entityAdded")
        }
        attachSurfaceIfReady()
        return true
    }

    @MainActor
    private func updateVisionSurface(
        _ content: RealityViewContent,
        proxy: GeometryProxy3D,
        revision: Int
    ) {
        guard prepareSurface(in: content, revision: revision) else { return }
        _ = scaleToFitWindow(videoEntity, proxy: proxy, content: content)
    }

    @MainActor
    private func scaleToFitWindow(
        _ entity: Entity,
        proxy: GeometryProxy3D,
        content: RealityViewContent
    ) -> SIMD3<Float>? {
        guard let component = entity.components[VideoPlayerComponent.self] else { return nil }
        let screenSize = component.playerScreenSize
        let resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : WindowPlaybackSurfaceGeometry.defaultSurfaceSize
        let sceneBounds = content.convert(
            proxy.frame(in: .local),
            from: .local,
            to: .scene
        )
        guard let layout = WindowPlaybackSurfaceGeometry.layout(
            surfaceSize: resolvedScreenSize,
            sceneCenter: sceneBounds.center,
            sceneExtents: sceneBounds.extents
        ) else {
            return nil
        }
        PlaybackSurfacePlacement.window(
            entity,
            sceneCenter: layout.sceneCenter
        )
        entity.scale = .init(repeating: layout.scale)
        let layoutSignature =
            "\(layout.sceneCenter)-\(layout.availableSize)-\(resolvedScreenSize)-\(layout.scale)"
        if componentObservation.shouldLogLayout(layoutSignature) {
            playbackVideoSurfaceLogger.notice(
                "window layout sceneCenter=\(String(describing: layout.sceneCenter), privacy: .public) sceneSize=\(String(describing: layout.availableSize), privacy: .public) screenSize=\(String(describing: resolvedScreenSize), privacy: .public) renderedSize=\(String(describing: layout.renderedSize), privacy: .public) scale=\(layout.scale)"
            )
        }
        return [
            layout.availableSize.x,
            layout.availableSize.y,
            Float(sceneBounds.extents.z)
        ]
    }

    @MainActor
    private func attachSurfaceIfReady() {
        logSurfaceFacts(reason: "attachCheck")
        // The runtime attachment belongs to the transition's target
        // presentation (the settled one when no transition is running). The
        // departing window surface stays mounted while the main window
        // dismissal completes, and re-attaching it on the replacement
        // technical session steals the attachment back from the immersive
        // surface, after which settlement can never commit and the open
        // rolls back at the executor deadline.
        let owningPresentation =
            appModel.presentationTransition?.targetPresentation
                ?? appModel.playbackPresentation
        guard owningPresentation == presentation else { return }
        guard videoEntity.isActive,
              let renderer = playbackRuntime.renderer,
              isActive,
              playbackRuntime.mediaFormatIsKnown,
              PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: presentation
              ) else { return }
        if let component {
            let recoveryAction = componentObservation.modeRecoveryAction(
                to: videoEntity,
                presentation: presentation,
                component: component,
                requiresImmersiveViewingModeSettlement:
                    requiresMainWindowModeSettlement
            )
            switch recoveryAction {
            case .none:
                break
            case .requestModesAgain:
                PlaybackRealityPresenter.reapplyDesiredModesAfterSceneActivation(
                    videoEntity,
                    presentation: presentation,
                    requestsSpatialVideoMode: playbackRuntime.requestsSpatialVideoMode
                )
            }
        }
        do {
            try playbackRuntime.attach(
                entityID: entityID,
                realityViewID: realityViewID,
                presentation: presentation
            )
            // The immersive-open race is only visible as the order of this
            // attach against the immersive surface's, so it must reach the
            // probe file, deduplicated per technical session.
            let attachProbeSignature = [
                "windowSurfaceAttached",
                presentation.rawValue,
                playbackRuntime.activeTechnicalSessionID ?? "none",
            ].joined(separator: "|")
            if componentObservation.shouldLogAttach(attachProbeSignature) {
                appModel.recordSurfaceInputProbe(
                    "windowSurfaceAttached presentation=\(presentation.rawValue) "
                    + "technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")"
                )
            }
            playbackRuntime.recordPresentationState(
                presentation: presentation,
                phase: presentationPhase,
                entityID: entityID,
                videoComponentRevision: playbackRuntime.videoComponentRevision,
                realityViewID: realityViewID,
                entityParentID: videoEntity.parent.map { String(describing: ObjectIdentifier($0)) },
                desiredImmersiveViewingMode: desiredImmersiveViewingMode,
                actualImmersiveViewingMode: actualImmersiveViewingMode,
                desiredViewingMode: component.map { String(describing: $0.desiredViewingMode) },
                actualViewingMode: component?.viewingMode.map { String(describing: $0) },
                desiredSpatialVideoMode: desiredSpatialVideoMode,
                actualSpatialVideoMode: actualSpatialVideoMode,
                componentRenderingStatus: component.map {
                    String(describing: $0.currentRenderingStatus)
                },
                displayedPixelBuffer: renderer.displayedPixelBuffer() != nil
            )
            logSurfaceFacts(reason: "attachCompleted")
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
            let failureSignature = [
                "attachFailed",
                error.localizedDescription,
                playbackRuntime.activeSessionID ?? "sessionNone"
            ].joined(separator: "|")
            if componentObservation.shouldLogState(failureSignature) {
                playbackVideoSurfaceLogger.error(
                    "surface attach failed presentation=\(presentation.rawValue, privacy: .public) entity=\(entityID, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
            surfaceActivation.requestRetry()
        }
    }

    private var entityID: String {
        playbackVideoEntityStore.hostedEntityID(
            for: presentation,
            during: appModel.presentationTransition
        )
    }

    private var realityViewID: String {
        "EnchronRealityView.mainWindow#\(ObjectIdentifier(videoEntity))"
    }

    private var component: VideoPlayerComponent? {
        videoEntity.components[VideoPlayerComponent.self]
    }

    private var desiredImmersiveViewingMode: String? {
        component.map { String(describing: $0.desiredImmersiveViewingMode) }
    }

    private var actualImmersiveViewingMode: String? {
        component?.immersiveViewingMode.map { String(describing: $0) }
    }

    private var desiredSpatialVideoMode: String? {
        component.map { String(describing: $0.desiredSpatialVideoMode) }
    }

    private var actualSpatialVideoMode: String? {
        component.map { String(describing: $0.spatialVideoMode) }
    }

    private var presentationPhase: PlaybackPresentationSettlementPhase {
        guard let component else { return .surfaceAttached }
        let requiresImmersiveViewingModeConfirmation: Bool
        if let transition = appModel.presentationTransition,
           (transition.previousPresentation == .panorama
                && transition.targetPresentation.usesMainWindow)
            || (transition.previousPresentation.usesMainWindow
                && transition.targetPresentation == .panorama) {
            requiresImmersiveViewingModeConfirmation = true
        } else {
            requiresImmersiveViewingModeConfirmation = false
        }
        let immersiveViewingModeIsSettled =
            SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: playbackRuntime.effectiveContentIsPanoramic,
                requiresTransitionConfirmation:
                    requiresImmersiveViewingModeConfirmation,
                desiredImmersiveViewingMode: String(
                    describing: component.desiredImmersiveViewingMode
                ),
                observedImmersiveViewingMode: component.immersiveViewingMode.map {
                    String(describing: $0)
                }
            )
        let viewingModeIsSettled =
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                observedViewingMode: component.viewingMode.map {
                    String(describing: $0)
                }
            )
        let renderingIsReady = component.currentRenderingStatus == .ready
        let hasPixels = playbackRuntime.renderer?.displayedPixelBuffer() != nil
        let isSettled = renderingIsReady
            && immersiveViewingModeIsSettled
            && viewingModeIsSettled
            && hasPixels
        let breakdown = [
            "settled=\(isSettled)",
            "ready=\(renderingIsReady)",
            "immersiveViewingMode=\(immersiveViewingModeIsSettled)",
            "viewingMode=\(viewingModeIsSettled)",
            "pixels=\(hasPixels)",
            "requiresImmersiveConfirmation=\(requiresImmersiveViewingModeConfirmation)",
            "presentation=\(presentation.rawValue)",
            "transition=\(appModel.presentationTransition?.targetPresentation.rawValue ?? "none")",
            "status=\(String(describing: component.currentRenderingStatus))",
            "wantImmersive=\(String(describing: component.desiredImmersiveViewingMode))",
            "gotImmersive=\(component.immersiveViewingMode.map { String(describing: $0) } ?? "none")",
            "wantViewing=\(String(describing: component.desiredViewingMode))",
            "gotViewing=\(component.viewingMode.map { String(describing: $0) } ?? "none")",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "panoramic=\(playbackRuntime.effectiveContentIsPanoramic)",
            "lifecycle=\(playbackRuntime.productLifecycle)",
        ].joined(separator: ",")
        if componentObservation.shouldLogPhase(breakdown) {
            appModel.recordSurfaceInputProbe("windowSettlement \(breakdown)")
        }
        return isSettled ? .settled : .surfaceAttached
    }

    private var requiresMainWindowModeSettlement: Bool {
        guard let transition = appModel.presentationTransition else { return false }
        return playbackRuntime.effectiveProjectionType != .flat
            && transition.previousPresentation == .panorama
            && transition.targetPresentation.usesMainWindow
    }

    private func logComponentState(reason: String) {
        logSurfaceFacts(reason: reason)
    }

    private func logSurfaceFacts(reason: String) {
        let component = videoEntity.components[VideoPlayerComponent.self]
        let renderer = playbackRuntime.renderer
        let isBound = renderer.map {
            PlaybackRealityPresenter.isBound(
                videoEntity,
                to: $0,
                presentation: presentation
            )
        } ?? false
        let diagnostics = playbackRuntime.diagnostics
        let firstEnqueue = diagnostics.enqueuedSampleCount > 0
        let displayedPixel = renderer?.displayedPixelBuffer() != nil
        let runtimeAttached = playbackRuntime.attachedPresentation == presentation
        let runtimeConsumer = playbackRuntime.rendererConsumerEntityID == entityID
        let stateSignature = [
            "active=\(videoEntity.isActive)",
            "surfaceActive=\(isActive)",
            "formatReady=\(playbackRuntime.mediaFormatIsKnown)",
            "rendererAvailable=\(renderer != nil)",
            "componentBound=\(isBound)",
            "runtimeAttached=\(runtimeAttached)",
            "runtimeConsumer=\(runtimeConsumer)",
            "componentRendering=\(String(describing: component?.currentRenderingStatus))",
            "rendererStatus=\(diagnostics.rendererStatus)",
            "rendererError=\(diagnostics.rendererError)",
            "firstEnqueue=\(firstEnqueue)",
            "displayedPixel=\(displayedPixel)"
        ].joined(separator: "|")
        guard componentObservation.shouldLogState(stateSignature) else { return }
        playbackVideoSurfaceLogger.notice(
            "surface facts reason=\(reason, privacy: .public) presentation=\(presentation.rawValue, privacy: .public) entity=\(entityID, privacy: .public) \(stateSignature, privacy: .public)"
        )
    }

    private func detachSurface() {
        guard playbackRuntime.attachedPresentation?.usesMainWindow == true else {
            return
        }
        playbackRuntime.detachSurface(entityID: entityID, realityViewID: realityViewID)
    }

    private func releaseSurface<Content: RealityViewContentProtocol>(from content: Content) {
        let ownsEntity = ownsPlaybackEntity
        if ownsEntity {
            content.remove(videoEntity)
        }
        releaseSurface(removingEntity: ownsEntity)
    }

    private func releaseSurface(removingEntity: Bool? = nil) {
        let removesEntity = removingEntity ?? ownsPlaybackEntity
        surfaceActivation.cancel()
        surfaceAccessibilityActivation.cancel()
        rendererTargetObservation.cancel()
        componentObservation.cancel()
        subtitleSurface.remove()
        guard removesEntity else { return }
        videoEntity.removeFromParent()
        if playbackVideoEntityStore.departingEntity === videoEntity {
            playbackVideoEntityStore.releaseDepartingEntity()
            detachSurface()
            return
        }
        let preservesPlaybackComponent = playbackRuntime.activeSessionID != nil
        if preservesPlaybackComponent == false {
            playbackVideoEntityStore.releasePlaybackComponent()
        }
        if let consumerPresentation = playbackRuntime.rendererConsumerPresentation,
           consumerPresentation.usesMainWindow,
           playbackRuntime.rendererConsumerEntityID == entityID {
            playbackRuntime.releaseRendererConsumer(
                presentation: consumerPresentation,
                entityID: entityID,
                preservingVideoComponent: preservesPlaybackComponent
            )
        }
        detachSurface()
    }

    private var ownsPlaybackEntity: Bool {
        playbackRuntime.rendererConsumerPresentation?.usesMainWindow == true
            || playbackRuntime.attachedPresentation?.usesMainWindow == true
    }

    private var preservesDepartingSurfaceForFade: Bool {
        guard let transition = appModel.presentationTransition else {
            return false
        }
        return transition.previousPresentation.usesMainWindow
            && presentation.usesMainWindow
            && transition.targetPresentation.usesImmersiveSpace
            && appModel.presentationSourceRendererMayRelease
    }

    private func releaseRendererOwnershipWhileKeepingVisibleSurface() {
        surfaceActivation.cancel()
        surfaceAccessibilityActivation.cancel()
        rendererTargetObservation.cancel()
        componentObservation.cancel()
        subtitleSurface.remove()
        guard let sourcePresentation = playbackRuntime.rendererConsumerPresentation,
              sourcePresentation.usesMainWindow,
              playbackRuntime.rendererConsumerEntityID == entityID else {
            return
        }
        playbackRuntime.releaseRendererConsumer(
            presentation: sourcePresentation,
            entityID: entityID,
            preservingVideoComponent: false
        )
        detachSurface()
    }

    private var activeSubtitleText: String? {
        let text = playbackRuntime.activeSubtitleCues
            .map(\.text)
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
