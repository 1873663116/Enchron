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
        #if os(visionOS)
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
        #endif
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

    #if os(visionOS)
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
    #endif
}

struct PlaybackVideoSurface: View {
    private static let subtitleControlSafeAreaFraction: Float = 0.32

    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore

    let presentation: PlaybackPresentation
    let isActive: Bool
    let viewportRefreshRevision: UInt64
    let onViewportRefreshApplied: @MainActor (UInt64) -> Void

    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var realityViewUpdateScheduler = PlaybackRealityViewUpdateScheduler()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var surfaceAccessibilityActivation =
        PlaybackSurfaceAccessibilityActivationObservation()
    @State private var rendererTargetObservation =
        PlaybackVideoRendererTargetObservation()
    @State private var componentObservation = PlaybackVideoComponentObservation()
    @State private var componentRevision = 0
    #if os(visionOS)
    @State private var surfaceRefreshTick = 0
    @State private var validVisionLayoutViewportRefreshRevision: UInt64?
    #endif

    private var videoEntity: Entity {
        playbackVideoEntityStore.hostedEntity(
            for: presentation,
            during: appModel.presentationTransition
        )
    }

    private var realityKitContentTypeScope: PlaybackRealityKitContentTypeScope? {
        PlaybackRealityKitContentTypeScope(runtime: playbackRuntime)
    }
    #if os(macOS)
    @State private var macOSWindowCamera = Entity()
    @State private var macOSWorld: Entity?
    @State private var macOSPlaybackSurfaceAnchor: Entity?
    @State private var isLoadingMacOSWorld = false
    @State private var macOSWorldLoadError: String?
    #endif

    @ViewBuilder
    var body: some View {
        ZStack {
            #if os(visionOS)
            visionSurface
            #else
            macOSSurface
            #endif

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

    #if os(visionOS)
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
        let viewportRefreshRevision = viewportRefreshRevision
        let revision = componentRevision &+ surfaceRefreshTick
        realityViewUpdateScheduler.schedule {
            guard Task.isCancelled == false else { return }
            updateVisionSurface(
                content,
                proxy: proxy,
                revision: revision,
                viewportRefreshRevision: viewportRefreshRevision
            )
        }
    }
    #else
    private var macOSSurface: some View {
        GeometryReader { geometry in
            ZStack {
                RealityView { content in
                    updateMacOSSurface(
                        &content,
                        canvasSize: geometry.size,
                        revision: componentRevision
                    )
                } update: { content in
                    updateMacOSSurface(
                        &content,
                        canvasSize: geometry.size,
                        revision: componentRevision
                    )
                }
                .realityViewCameraControls(presentation == .docked ? .orbit : .none)
                .background(.black)
                .gesture(surfaceTapGesture)

                if presentation == .docked, isLoadingMacOSWorld {
                    ProgressView("Loading environment…")
                }

                if presentation == .docked, let macOSWorldLoadError {
                    ContentUnavailableView(
                        "Environment Unavailable",
                        systemImage: "cube.transparent",
                        description: Text(macOSWorldLoadError)
                    )
                }

            }
            .task(id: presentation) {
                guard presentation == .docked else { return }
                await loadMacOSWorldIfNeeded()
                componentRevision &+= 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MacPlayback-\(presentation.rawValue)-SceneHost")
        .accessibilityValue(playbackRuntime.lifecycle.label)
        .onDisappear {
            releaseSurface()
        }
    }
    #endif

    private var surfaceTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(videoEntity)
            .onEnded { _ in
                toggleControlsFromSurface()
            }
    }

    private func toggleControlsFromSurface() {
        Task { @MainActor in
            // A RealityKit entity can receive the same spatial tap that
            // activates SwiftUI playback chrome above it. Yield so the
            // control action can register its interaction first; a genuine
            // video-surface tap has no competing control action and still
            // toggles the controls on this run-loop turn.
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                PlaybackSurfaceInputAction.perform(
                    .spatialTap,
                    appModel: appModel
                )
            }
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

    #if os(visionOS)
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
    #endif

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

        #if os(macOS)
        let needsInsertion = presentation.usesMainWindow
            && content.entities.contains(where: { $0 === videoEntity }) == false
        #else
        let needsInsertion = content.entities.contains(where: { $0 === videoEntity }) == false
        #endif
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
                && PlaybackPresentationTransitionAppearance
                    .shouldAnimateWindowVideoEntity(
                        transition: appModel.presentationTransition,
                        visualCutoverMayBegin:
                            appModel.presentationVisualCutoverMayBegin
                    )
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
            frame: playbackRuntime.activeSubtitleFrame,
            emitEnablementWrite: appModel.recordSurfaceInputProbe
        )
        if needsInsertion {
            logComponentState(reason: "entityAdded")
        }
        return true
    }

    #if os(visionOS)
    @MainActor
    private func updateVisionSurface(
        _ content: RealityViewContent,
        proxy: GeometryProxy3D,
        revision: Int,
        viewportRefreshRevision: UInt64
    ) {
        validVisionLayoutViewportRefreshRevision = nil
        guard prepareSurface(in: content, revision: revision) else { return }
        guard scaleToFitWindow(
            videoEntity,
            proxy: proxy,
            content: content
        ) != nil else {
            return
        }
        validVisionLayoutViewportRefreshRevision = viewportRefreshRevision
        attachSurfaceIfReady()
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

    #else
    @MainActor
    private func updateMacOSSurface(
        _ content: inout RealityViewCameraContent,
        canvasSize: CGSize,
        revision: Int
    ) {
        content.camera = .virtual
        if let macOSWorld {
            if content.entities.contains(where: { $0 === macOSWorld }) == false {
                content.add(macOSWorld)
            }
            macOSWorld.isEnabled = presentation == .docked
        }
        guard presentation != .panorama else {
            playbackRuntime.lastErrorMessage = "Panorama presentation is available on visionOS."
            return
        }
        if presentation == .docked, macOSPlaybackSurfaceAnchor == nil {
            if let macOSWorldLoadError {
                playbackRuntime.lastErrorMessage = macOSWorldLoadError
            }
            return
        }
        guard prepareSurface(in: content, revision: revision) else {
            content.cameraTarget = nil
            return
        }
        switch presentation {
        case .window, .portal:
            if content.entities.contains(where: { $0 === videoEntity }) == false {
                content.add(videoEntity)
            }
            PlaybackSurfacePlacement.window(videoEntity)
            configureMacOSWindowCamera(in: &content, canvasSize: canvasSize)
        case .docked:
            content.remove(macOSWindowCamera)
            guard let macOSPlaybackSurfaceAnchor else { return }
            PlaybackSurfacePlacement.dock(
                videoEntity,
                to: macOSPlaybackSurfaceAnchor,
                transform: .init(
                    distance: appModel.screenDepthOffset,
                    elevationDegrees: appModel.screenViewAngle,
                    scale: appModel.screenScale
                )
            )
        case .panorama:
            return
        }
        content.cameraTarget = presentation == .docked ? videoEntity : nil
        attachSurfaceIfReady()
    }

    @MainActor
    private func configureMacOSWindowCamera(
        in content: inout RealityViewCameraContent,
        canvasSize: CGSize
    ) {
        let geometry = MacWindowPlaybackCameraGeometry.resolve(
            screenSize: macOSWindowScreenSize,
            canvasSize: canvasSize
        )
        if content.entities.contains(where: { $0 === macOSWindowCamera }) == false {
            content.add(macOSWindowCamera)
        }
        macOSWindowCamera.components.set(
            PerspectiveCameraComponent(
                near: 0.01,
                far: 100,
                fieldOfViewInDegrees: MacWindowPlaybackCameraGeometry.fieldOfViewInDegrees,
                fieldOfViewOrientation: .vertical
            )
        )
        macOSWindowCamera.look(
            at: .zero,
            from: [0, 0, geometry.distance],
            relativeTo: nil
        )
        let signature = "macOS-window-\(canvasSize)-\(geometry.screenSize)-\(geometry.distance)"
        if componentObservation.shouldLogLayout(signature) {
            playbackVideoSurfaceLogger.notice(
                "macOS window camera canvasSize=\(String(describing: canvasSize), privacy: .public) screenSize=\(String(describing: geometry.screenSize), privacy: .public) distance=\(geometry.distance)"
            )
        }
    }

    private var macOSWindowScreenSize: SIMD2<Float> {
        if let componentSize = component?.playerScreenSize,
           componentSize.x > 0,
           componentSize.y > 0 {
            return componentSize
        }
        guard let resolution = playbackRuntime.displayMediaProfile?.resolution,
              resolution.width > 0,
              resolution.height > 0 else { return .zero }
        let output = playbackRuntime.effectiveStereoLayout.outputDimensions(
            inputWidth: resolution.width,
            inputHeight: resolution.height
        )
        guard output.width > 0, output.height > 0 else { return .zero }
        return [Float(output.width) / Float(output.height), 1]
    }

    @MainActor
    private func loadMacOSWorldIfNeeded() async {
        guard macOSWorld == nil,
              isLoadingMacOSWorld == false,
              macOSWorldLoadError == nil else { return }
        isLoadingMacOSWorld = true
        defer { isLoadingMacOSWorld = false }
        do {
            let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
            macOSPlaybackSurfaceAnchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)
            world.isEnabled = false
            macOSWorld = world
            playbackVideoSurfaceLogger.notice("macOS RCP world loaded for shared playback RealityView")
        } catch {
            macOSWorldLoadError = error.localizedDescription
            playbackVideoSurfaceLogger.error(
                "macOS RCP world load failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
    #endif

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
        #if os(visionOS)
        guard let validVisionLayoutViewportRefreshRevision else { return }
        #endif
        guard videoEntity.isActive,
              let renderer = playbackRuntime.renderer,
              isActive,
              playbackRuntime.mediaFormatIsKnown,
              PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: presentation
              ) else { return }
        #if os(visionOS)
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
        #endif
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
            if presentation == .portal,
               validVisionLayoutViewportRefreshRevision > 0 {
                onViewportRefreshApplied(
                    validVisionLayoutViewportRefreshRevision
                )
            }
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
        #if os(macOS)
        "EnchronRealityView.macOS#\(ObjectIdentifier(videoEntity))"
        #else
        "EnchronRealityView.mainWindow#\(ObjectIdentifier(videoEntity))"
        #endif
    }

    private var component: VideoPlayerComponent? {
        videoEntity.components[VideoPlayerComponent.self]
    }

    private var desiredImmersiveViewingMode: String? {
        #if os(visionOS)
        component.map { String(describing: $0.desiredImmersiveViewingMode) }
        #else
        nil
        #endif
    }

    private var actualImmersiveViewingMode: String? {
        #if os(visionOS)
        component?.immersiveViewingMode.map { String(describing: $0) }
        #else
        nil
        #endif
    }

    private var desiredSpatialVideoMode: String? {
        #if os(visionOS)
        component.map { String(describing: $0.desiredSpatialVideoMode) }
        #else
        nil
        #endif
    }

    private var actualSpatialVideoMode: String? {
        #if os(visionOS)
        component.map { String(describing: $0.spatialVideoMode) }
        #else
        nil
        #endif
    }

    private var presentationPhase: PlaybackPresentationSettlementPhase {
        guard let component else { return .surfaceAttached }
        let requiresImmersiveViewingModeConfirmation: Bool
        #if os(visionOS)
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
        #else
        requiresImmersiveViewingModeConfirmation = false
        let immersiveViewingModeIsSettled = true
        #endif
        let viewingModeIsSettled =
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                observedViewingMode: component.viewingMode.map {
                    String(describing: $0)
                }
            )
        let renderingIsReady = component.currentRenderingStatus == .ready
        let renderer = playbackRuntime.renderer
        let diagnostics = playbackRuntime.diagnostics
        let debugSnapshot = playbackRuntime.debugSnapshot()
        let rendererState = debugSnapshot?.rendererState
        let audioRendererState = debugSnapshot?.audioRendererState
        let hasPixels = renderer?.displayedPixelBuffer() != nil
        let displayedFrameObservationCount = (
            rendererState?.displayedFrameObservationCount
        ).map(String.init) ?? "none"
        let timelineConfigured = rendererState.map { String($0.timelineConfigured) } ?? "none"
        let synchronizerTime = rendererState.map { String($0.currentTimeSeconds) } ?? "none"
        let synchronizerRate = rendererState.map { String($0.rate) } ?? "none"
        let actualTimebaseRate = rendererState?.actualTimebaseRate.map { String($0) } ?? "none"
        let effectiveTimebaseRate = rendererState?.effectiveTimebaseRate.map { String($0) } ?? "none"
        let timebaseSourceType = rendererState?.timebaseSourceType ?? "none"
        let timebaseSourceTime = rendererState?.timebaseSourceTimeSeconds.map { String($0) }
            ?? "none"
        let timebaseUltimateSourceTime = rendererState?.timebaseUltimateSourceTimeSeconds.map {
            String($0)
        } ?? "none"
        let streamEpoch = rendererState.map { String($0.streamEpoch) } ?? "none"
        let lastVideoPTS = debugSnapshot?.lastVideoSample.map {
            String($0.presentationTimeSeconds)
        } ?? "none"
        let lastVideoDTS = debugSnapshot?.lastVideoSample?.decodeTimeSeconds.map { String($0) }
            ?? "none"
        let decoderBootstrapComplete = debugSnapshot?.decoderBootstrap.map {
            String($0.complete)
        } ?? "none"
        let acceptedRendererInputCount = debugSnapshot.map {
            String($0.acceptedRendererInputCount)
        } ?? "none"
        let backpressureCount = debugSnapshot.map { String($0.backpressureCount) } ?? "none"
        let timelineRecovery = debugSnapshot?.timelineProgressRecovery
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
            "requiresFlushToResumeDecoding=\(renderer.map { String($0.requiresFlushToResumeDecoding) } ?? "none")",
            "isReadyForMoreMediaData=\(renderer.map { String($0.isReadyForMoreMediaData) } ?? "none")",
            "rendererStatus=\(renderer.map { String(describing: $0.status) } ?? "none")",
            "rendererError=\(renderer?.error?.localizedDescription ?? "none")",
            "diagnosticRendererStatus=\(diagnostics.rendererStatus)",
            "diagnosticRendererError=\(diagnostics.rendererError)",
            "enqueuedSampleCount=\(diagnostics.enqueuedSampleCount)",
            "displayedFrameObservationCount=\(displayedFrameObservationCount)",
            "flushCount=\(rendererState.map { String($0.flushCount) } ?? "none")",
            "timelineConfigured=\(timelineConfigured)",
            "synchronizerTime=\(synchronizerTime)",
            "synchronizerRate=\(synchronizerRate)",
            "actualTimebaseRate=\(actualTimebaseRate)",
            "effectiveTimebaseRate=\(effectiveTimebaseRate)",
            "timebaseSourceType=\(timebaseSourceType)",
            "timebaseSourceTime=\(timebaseSourceTime)",
            "timebaseUltimateSourceTime=\(timebaseUltimateSourceTime)",
            "streamEpoch=\(streamEpoch)",
            "lastVideoPTS=\(lastVideoPTS)",
            "lastVideoDTS=\(lastVideoDTS)",
            "decoderBootstrapComplete=\(decoderBootstrapComplete)",
            "acceptedRendererInputCount=\(acceptedRendererInputCount)",
            "backpressureCount=\(backpressureCount)",
            "lastAudioPTS=\(debugSnapshot?.lastAudioSample.map { String($0.presentationTimeSeconds) } ?? "none")",
            "audioSampleBufferCount=\(debugSnapshot.map { String($0.audioSampleBufferCount) } ?? "none")",
            "audioRendererEnqueuedSampleBufferCount=\(audioRendererState.map { String($0.enqueuedSampleBufferCount) } ?? "none")",
            "audioRendererStatus=\(audioRendererState?.status ?? "none")",
            "audioRendererError=\(audioRendererState?.error ?? "none")",
            "audioRendererReadyForMoreMediaData=\(audioRendererState.map { String($0.isReadyForMoreMediaData) } ?? "none")",
            "audioRendererHasSufficientMediaData=\(audioRendererState.map { String($0.hasSufficientMediaDataForReliablePlaybackStart) } ?? "none")",
            "timelineRecovery=\(timelineRecovery?.outcome.rawValue ?? "none")",
            "timelineRecoveryIncident=\(timelineRecovery.map { String($0.incidentID) } ?? "none")",
            "timelineRecoverySource=\(timelineRecovery?.detectionSource?.rawValue ?? "none")",
            "timelineRecoveryLanes=\(timelineRecovery?.detectingLanes.joined(separator: "+") ?? "none")",
            "timelineRecoveryWatchdogCause=\(timelineRecovery?.watchdogCause?.rawValue ?? "none")",
            "timelineRecoveryWatchdogCount=\(timelineRecovery?.watchdogConsecutiveObservationCount.map(String.init) ?? "none")",
            "timelineRecoveryFrozenMediaTime=\(timelineRecovery.map { String($0.frozenMediaTimeSeconds) } ?? "none")",
            "timelineRecoveryReanchorHostTime=\(timelineRecovery?.reanchorHostTimeSeconds.map { String($0) } ?? "none")",
            "timelineRecoveryPostMediaTime=\(timelineRecovery?.postRecoveryMediaTimeSeconds.map { String($0) } ?? "none")",
            "timelineRecoveryAttemptCount=\(timelineRecovery.map { String($0.attemptCount) } ?? "none")",
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
        subtitleSurface.remove(emitEnablementWrite: appModel.recordSurfaceInputProbe)
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
        subtitleSurface.remove(emitEnablementWrite: appModel.recordSurfaceInputProbe)
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
