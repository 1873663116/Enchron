import AVFoundation
import RealityKit
import OSLog
import PlaybackCore
import SwiftUI

private let playbackVideoSurfaceLogger = Logger(
    subsystem: "com.xiongzhipeng.XTransferPlayer",
    category: "PlaybackVideoSurface"
)

enum PlaybackSettlementProbeSignature {
    private static let fastChangingFieldPrefixes = [
        "synchronizerTime=",
        "timebaseSourceTime=",
        "timebaseUltimateSourceTime=",
        "lastVideoPTS=",
        "lastVideoDTS=",
        "lastAudioPTS=",
        "enqueuedSampleCount=",
        "acceptedRendererInputCount=",
        "backpressureCount=",
        "audioSampleBufferCount=",
        "audioRendererEnqueuedSampleBufferCount=",
        "displayedFrameObservationCount="
    ]

    static func make(fields: [String]) -> String {
        fields
            .filter { field in
                !fastChangingFieldPrefixes.contains { field.hasPrefix($0) }
            }
            .joined(separator: ",")
    }
}

@MainActor
private final class PlaybackVideoComponentObservation {
    private var entityID: ObjectIdentifier?
    private var contentTypeSessionID: String?
    private var subscriptions: [EventSubscription] = []
    private var lastLayoutSignature: String?
    private var lastStateSignature: String?
    private var lastAttachSignature: String?
    private var lastPhaseSignature: String?
    private var lastPhaseEmission: Date?
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

    func shouldLogPhase(
        _ signature: String,
        heartbeat: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        let changed = lastPhaseSignature != signature
        let heartbeatDue = lastPhaseEmission.map {
            now.timeIntervalSince($0) >= heartbeat
        } ?? true
        guard changed || heartbeatDue else { return false }
        lastPhaseSignature = signature
        lastPhaseEmission = now
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

public struct PlaybackVideoSurface: View {
    private static let subtitleControlSafeAreaFraction: Float = 0.32

    @Environment(PlaybackSessionModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore

    let presentation: PlaybackPresentation
    let isActive: Bool
    let surfaceTapIsEnabled: Bool
    let viewportRefreshRevision: UInt64
    let onViewportRefreshApplied: @MainActor (UInt64) -> Void

    public init(
        presentation: PlaybackPresentation,
        isActive: Bool,
        surfaceTapIsEnabled: Bool,
        viewportRefreshRevision: UInt64,
        onViewportRefreshApplied: @escaping @MainActor (UInt64) -> Void
    ) {
        self.presentation = presentation
        self.isActive = isActive
        self.surfaceTapIsEnabled = surfaceTapIsEnabled
        self.viewportRefreshRevision = viewportRefreshRevision
        self.onViewportRefreshApplied = onViewportRefreshApplied
    }

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
    @State private var validVisionLayoutViewportRefreshRevision: UInt64?
    @State private var surfaceVerticalFill: Float = 1

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
    public var body: some View {
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
            .simultaneousGesture(surfaceTapGesture)
        }
        .frame(depth: realityViewDepth)
        .task(id: surfaceReadinessKey) {
            await retrySurfaceAttachment()
        }
        .onChange(of: playbackRuntime.videoComponentRevision) {
            surfaceRefreshTick &+= 1
        }
        .onChange(of: appModel.windowChromeOcclusion) {
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
    private func toggleControlsFromAccessibilityActivation() {
        withAnimation(.easeInOut(duration: 0.25)) {
            PlaybackSurfaceInputAction.perform(
                .accessibilityActivate,
                appModel: appModel
            )
        }
    }

    private var surfaceTapGesture: some Gesture {
        TapGesture()
            .targetedToEntity(playbackVideoEntityStore.windowInteractionSurface)
            .onEnded { value in
                guard surfaceTapIsEnabled,
                      PlaybackSurfaceInputOwnership.acceptsSpatialTapTarget(
                        value.entity,
                        for: presentation
                      ) else {
                    appModel.recordSurfaceInputProbe(
                        "spatialTap entity=\(value.entity.name)"
                            + " accepted=false presentation=\(presentation.rawValue)"
                    )
                    return
                }
                appModel.recordSurfaceInputProbe(
                    "spatialTap entity=\(value.entity.name)"
                        + " accepted=true presentation=\(presentation.rawValue)"
                )
                withAnimation(.easeInOut(duration: 0.25)) {
                    PlaybackSurfaceInputAction.perform(
                        .spatialTap,
                        appModel: appModel
                    )
                }
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
            SurfaceInputProbes.record(
                "rendererOwnership.prepareSurface outcome=noRendererYet"
                    + " presentation=\(presentation.rawValue)"
                    + " entity=\(PlaybackRuntime.probeEntity(entityID))"
                    + " formatKnown=\(playbackRuntime.mediaFormatIsKnown)"
                    + " renderer=\(playbackRuntime.renderer == nil ? "none" : "present")"
            )
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
            playbackRuntime.setUserVisibleIssue(.surfaceAttachmentFailed)
            playbackVideoSurfaceLogger.error(
                "renderer consumer claim failed presentation=\(presentation.rawValue, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
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
        let installedOcclusion = appModel.windowChromeOcclusion
        PlaybackWindowInteractionSurface.install(
            playbackVideoEntityStore.windowInteractionSurface,
            on: videoEntity,
            screenSize: component?.playerScreenSize ?? .zero,
            verticalFill: surfaceVerticalFill,
            occlusion: installedOcclusion
        )
        appModel.recordSurfaceInputProbe(
            "windowColliderInstall topFraction=\(installedOcclusion.topFraction)"
                + " menu=\(installedOcclusion.secondaryMenuIsPresented)"
                + " verticalFill=\(surfaceVerticalFill)"
                + " screenSize=\(component?.playerScreenSize ?? .zero)"
                + " hasTarget=\(playbackVideoEntityStore.windowInteractionSurface.components[InputTargetComponent.self] != nil)"
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
            emitEnablementWrite: { appModel.recordSurfaceInputProbe($0) }
        )
        if needsInsertion {
            logComponentState(reason: "entityAdded")
        }
        return true
    }

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
        let verticalFill = layout.availableSize.y > 0
            ? layout.renderedSize.y / layout.availableSize.y
            : 1
        if verticalFill.isFinite, verticalFill > 0, surfaceVerticalFill != verticalFill {
            surfaceVerticalFill = verticalFill
        }
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
            let reportedTechnicalSessionID = playbackRuntime.activeTechnicalSessionID
            let reportedVideoComponentRevision = playbackRuntime.videoComponentRevision
            let reportedStreamEpoch = playbackRuntime.debugSnapshot()?.streamEpoch
            let currentPixelIdentityWasAccepted = playbackRuntime.recordPresentationState(
                presentation: presentation,
                phase: presentationPhase,
                entityID: entityID,
                technicalSessionID: reportedTechnicalSessionID,
                videoComponentRevision: reportedVideoComponentRevision,
                streamEpoch: reportedStreamEpoch,
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
            if SpatialPlatformImmersiveExitWindowRevealPolicy.shouldBeginVisualCutover(
                transition: appModel.presentationTransition,
                surfacePresentation: presentation,
                targetSurfacePixelIdentityIsCurrent: currentPixelIdentityWasAccepted
            ), appModel.presentationVisualCutoverMayBegin == false,
               appModel.beginPresentationVisualCutover() {
                appModel.recordSurfaceInputProbe(
                    "portalVisualCutover source=windowSurface"
                        + " technicalSession=\(reportedTechnicalSessionID ?? "none")"
                        + " videoComponentRevision=\(reportedVideoComponentRevision)"
                        + " streamEpoch=\(reportedStreamEpoch.map(String.init) ?? "none")"
                        + " animated=false"
                )
            }
            if presentation == .portal,
               validVisionLayoutViewportRefreshRevision > 0 {
                onViewportRefreshApplied(
                    validVisionLayoutViewportRefreshRevision
                )
            }
            logSurfaceFacts(reason: "attachCompleted")
        } catch {
            playbackRuntime.setUserVisibleIssue(.surfaceAttachmentFailed)
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
        let settlementFields = [
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
        ]
        let breakdown = settlementFields.joined(separator: ",")
        let settlementSignature = PlaybackSettlementProbeSignature.make(
            fields: settlementFields
        )
        if componentObservation.shouldLogPhase(
            settlementSignature,
            heartbeat: 2
        ) {
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
        subtitleSurface.remove {
            appModel.recordSurfaceInputProbe($0)
        }
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
        subtitleSurface.remove {
            appModel.recordSurfaceInputProbe($0)
        }
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
