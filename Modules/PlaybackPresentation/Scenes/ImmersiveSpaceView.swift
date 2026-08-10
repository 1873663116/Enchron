import AVFoundation
import OSLog
import PlaybackFeature
import PlaybackPresentation
import RealityKit
import RealityKitScripting
import SwiftUI
import UIKit
import simd

@MainActor
enum EnvironmentSceneAppearanceApplier {
    static let skyboxName = "skybox"
    static let scenicPlaceholderName = "EnchronScenicPlaceholder"
    static let lightSkyboxOpacity: Float = 1
    static let darkSkyboxOpacity: Float = 0.35

    @discardableResult
    static func apply(
        environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect?,
        to world: Entity
    ) -> Float? {
        guard let skybox = world.findEntity(named: skyboxName) else {
            return nil
        }

        if environment == .skybox {
            skybox.isEnabled = true
            skybox.components.set(OpacityComponent(opacity: 1))
            world.findEntity(named: scenicPlaceholderName)?.removeFromParent()
            return 1
        }

        skybox.isEnabled = false
        let resolvedEffect = effect ?? .inactiveFallback
        let opacity = switch resolvedEffect {
        case .light: lightSkyboxOpacity
        case .dark: darkSkyboxOpacity
        }
        let color = scenicColor(for: environment, effect: resolvedEffect)
        let placeholder: ModelEntity
        if let existing = world.findEntity(named: scenicPlaceholderName) as? ModelEntity {
            placeholder = existing
            placeholder.model?.materials = [placeholderMaterial(color: color)]
        } else {
            placeholder = ModelEntity(
                mesh: .generateSphere(radius: 50),
                materials: [placeholderMaterial(color: color)]
            )
            placeholder.name = scenicPlaceholderName
            world.addChild(placeholder)
        }
        placeholder.isEnabled = true
        placeholder.components.set(OpacityComponent(opacity: opacity))
        return opacity
    }

    static func clear(in world: Entity) {
        world.findEntity(named: skyboxName)?.isEnabled = false
        world.findEntity(named: scenicPlaceholderName)?.isEnabled = false
    }

    private static func scenicColor(
        for environment: SpatialSceneDomain.CinemaEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) -> UIColor {
        let components: (CGFloat, CGFloat, CGFloat) = switch environment {
        case .scenicOne: (0.86, 0.48, 0.52)
        case .scenicTwo: (0.48, 0.78, 0.58)
        case .scenicThree: (0.46, 0.66, 0.88)
        case .skybox: (0.46, 0.66, 0.88)
        }
        let brightness: CGFloat = effect == .light ? 1 : 0.46
        return UIColor(
            red: components.0 * brightness,
            green: components.1 * brightness,
            blue: components.2 * brightness,
            alpha: 1
        )
    }

    private static func placeholderMaterial(color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .front
        return material
    }
}

@MainActor
private final class WorldSceneState {
    var entity: Entity?
    var playbackSurfaceAnchor: Entity?
    var appliedEnvironment: SpatialSceneDomain.CinemaEnvironment?
    var appliedEnvironmentEffect: SpatialSceneDomain.EnvironmentEffect?
    var isLoading = false
    var hasFailed = false
}

@MainActor
enum SpatialPresentationRefreshTrigger: CaseIterable {
    case viewingModeDidChange
    case immersiveViewingModeDidChange
    case immersiveViewingModeDidTransition
    case spatialVideoModeDidChange
    case renderingStatusDidChange
    case contentTypeDidChange
}

@MainActor
private final class SpatialPresentationObservation {
    private var entityID: ObjectIdentifier?
    private var contentTypeSessionID: String?
    private var subscriptions: [EventSubscription] = []
    private let modeRequestRetry = PlaybackModeRequestRetry()
    private var lastSurfaceReadinessSignatureByReason: [String: String] = [:]

    func observe(
        _ entity: Entity,
        in content: RealityViewContent,
        contentTypeSessionID: String?,
        onChange: @escaping @MainActor () -> Void,
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
        prepareForReplacementEntity()
        entityID = nextEntityID
        self.contentTypeSessionID = contentTypeSessionID
        subscriptions = [
            content.subscribe(to: VideoPlayerEvents.ViewingModeDidChange.self, on: entity) { _ in
                Task { @MainActor in
                    onChange()
                }
            },
            content.subscribe(to: VideoPlayerEvents.ImmersiveViewingModeDidChange.self, on: entity) { _ in
                Task { @MainActor in
                    onChange()
                }
            },
            content.subscribe(to: VideoPlayerEvents.ImmersiveViewingModeDidTransition.self, on: entity) { _ in
                Task { @MainActor in
                    onChange()
                }
            },
            content.subscribe(to: VideoPlayerEvents.SpatialVideoModeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange() }
            },
            content.subscribe(to: VideoPlayerEvents.RenderingStatusDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange() }
            }
        ]
        if let contentTypeSessionID {
            // ContentTypeDidChange doesn't expose its source Entity. Capture
            // the current session while leaving the subscription intact across
            // accepted format revisions; RealityKit doesn't promise a replay.
            subscriptions.append(
                content.subscribe(to: VideoPlayerEvents.ContentTypeDidChange.self) { event in
                    let contentType = String(describing: event.contentType)
                    Task { @MainActor in
                        onContentTypeDidChange(contentType, contentTypeSessionID)
                        onChange()
                    }
                }
            )
        }
    }

    func prepareForReplacementEntity() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
        contentTypeSessionID = nil
        lastSurfaceReadinessSignatureByReason.removeAll()
    }

    func cancel() {
        prepareForReplacementEntity()
        modeRequestRetry.reset()
    }

    func shouldLogSurfaceReadiness(
        reason: String,
        signature: String
    ) -> Bool {
        guard lastSurfaceReadinessSignatureByReason[reason] != signature else {
            return false
        }
        lastSurfaceReadinessSignatureByReason[reason] = signature
        return true
    }

    func modeRecoveryAction(
        to entity: Entity,
        presentation: PlaybackPresentation,
        component: VideoPlayerComponent,
        projection: PlaybackModel.ProjectionType,
        sourceContentKind: PlaybackModel.SourceVideoContentKind,
        provenance: MediaFormatProvenance,
        observedContentType: String
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
            contentTypeMatchesProjection: presentation != .panorama
                || SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                    projection: projection,
                    sourceContentKind: sourceContentKind,
                    provenance: provenance,
                    observedContentType: observedContentType
                )
        )
    }
}

public struct ImmersiveSpaceView: View {
    // Apple's own immersive-media sample receives the controls-summoning
    // pinch on an invisible collision entity with an input target; the
    // transparent SwiftUI attachment was never hit by real gaze (8/8 wearer
    // pinches arrived untargeted, 2026-08-10), so the shell is the receiver.
    private static let collisionShellInputShelved = false

    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackVideoEntityStore.self) private var playbackVideoEntityStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var world = WorldSceneState()
    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var realityViewUpdateScheduler = PlaybackRealityViewUpdateScheduler()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var surfaceAccessibilityActivation =
        PlaybackSurfaceAccessibilityActivationObservation()
    @State private var rendererTargetObservation =
        PlaybackVideoRendererTargetObservation()
    @State private var presentationObservation = SpatialPresentationObservation()
    @State private var surfaceRefreshTick = 0
    @State private var hasRecordedCollisionShellShelved = false
    private let logger = Logger(subsystem: "app.enchron", category: "SpatialSurface")

    private var videoEntity: Entity {
        playbackVideoEntityStore.hostedEntity(
            for: requestedPresentation,
            during: appModel.presentationTransition
        )
    }

    private var panoramaInteractionSurface: Entity {
        playbackVideoEntityStore.panoramaInteractionSurface
    }

    /// Diagnostic collider locked to the wearer's head, two meters straight
    /// ahead. It is reachable from any gaze direction and any room position,
    /// so a miss here rules geometry out of the spatial input question.
    @State private var headInputProbe: Entity = {
        let anchor = AnchorEntity(.head, trackingMode: .continuous)
        let panel = Entity()
        panel.name = "EnchronHeadInput.probe"
        panel.position = [0, 0, -2]
        panel.components.set(InputTargetComponent())
        panel.components.set(
            CollisionComponent(shapes: [.generateBox(size: [6, 6, 0.01])])
        )
        anchor.addChild(panel)
        return anchor
    }()

    private var realityKitContentTypeScope: PlaybackRealityKitContentTypeScope? {
        PlaybackRealityKitContentTypeScope(runtime: playbackRuntime)
    }

    public init() {}

    private var requestedPresentation: PlaybackPresentation {
        guard let transition = appModel.presentationTransition else {
            return appModel.playbackPresentation
        }
        if transition.previousPresentation.usesImmersiveSpace,
           transition.targetPresentation.usesMainWindow,
           appModel.presentationSourceRendererMayRelease == false {
            return transition.previousPresentation
        }
        return transition.targetPresentation
    }

    private var requestedEnvironmentContext: EnvironmentContext {
        guard let transition = appModel.presentationTransition else {
            return appModel.environmentContext
        }
        if transition.previousPresentation.usesImmersiveSpace,
           transition.targetPresentation.usesMainWindow,
           appModel.presentationSourceRendererMayRelease == false {
            return transition.previousEnvironment
        }
        return transition.targetEnvironment
    }

    public var body: some View {
        RealityView { content in
            scheduleSpatialSurfaceUpdate(content)
        } update: { content in
            scheduleSpatialSurfaceUpdate(content)
        }
        // realityScripting installs its own targeted SpatialTapGesture to feed
        // TapGestureEvent to scripts. It sits inside this view, so an ordinary
        // .gesture here loses every pinch to it; recognizing simultaneously is
        // what lets both the script system and playback see the tap.
        .realityScripting()
        .simultaneousGesture(spatialSurfaceTapGesture)
        .allowsHitTesting(spatialPresentationAcceptsInput)
        .onDisappear {
            realityViewUpdateScheduler.cancel()
            surfaceAccessibilityActivation.cancel()
            releaseSpatialSurface()
        }
        .task(id: spatialSurfaceReadinessKey) {
            await retrySpatialSurfaceAttachment()
        }
        .onChange(of: playbackRuntime.videoComponentRevision) {
            surfaceRefreshTick &+= 1
        }
        .onChange(of: spatialPresentationAcceptsInput, initial: true) { _, accepts in
            appModel.recordSurfaceInputProbe("acceptsInput=\(accepts)")
        }
        .onChange(of: appModel.showControls, initial: true) { _, visible in
            synchronizeControlsWindow(visible: visible)
        }
        .onChange(of: appModel.presentationTransition?.id) { _, transitionID in
            guard transitionID == nil else { return }
            synchronizeControlsWindow(visible: appModel.showControls)
        }
        .onChange(of: realityKitContentTypeScope) { _, scope in
            playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(scope)
            surfaceRefreshTick &+= 1
        }
    }

    private func scheduleSpatialSurfaceUpdate(
        _ content: RealityViewContent
    ) {
        let revision = surfaceRefreshTick
        // Read the observable placement synchronously inside RealityView's
        // update transaction. Reading it only from the deferred task prevents
        // SwiftUI from scheduling another update when a setting changes.
        let dockedPlacement = currentDockedSurfaceTransform
        realityViewUpdateScheduler.schedule {
            if needsWorld {
                await loadWorld(into: content)
            }
            update(
                content,
                revision: revision,
                dockedPlacement: dockedPlacement
            )
        }
    }

    private var currentDockedSurfaceTransform: PlaybackSurfaceTransform {
        PlaybackSurfaceTransform(
            distance: appModel.screenDepthOffset,
            elevationDegrees: appModel.screenViewAngle,
            scale: appModel.screenScale
        )
    }

    private var needsWorld: Bool {
        requestedPresentation == .docked
            || (requestedPresentation.usesMainWindow
                && requestedEnvironmentContext.environment != nil)
    }

    private var spatialPresentationOpacity: Double {
        PlaybackPresentationTransitionAppearance.opacity(
            for: requestedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition,
            visualCutoverMayBegin: appModel.presentationVisualCutoverMayBegin
        )
    }

    private var spatialPresentationAcceptsInput: Bool {
        PlaybackPresentationTransitionAppearance.acceptsInput(
            for: requestedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
        )
    }

    private var spatialSurfaceTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                // Every entity in this RealityView is playback surface (video,
                // collision shell, head receiver, attachments); the controls
                // live in their own window scene and never route here. The
                // old videoEntity-only filter silently dropped the pinches
                // the collision shell delivered.
                appModel.recordSurfaceInputProbe(
                    "spatialTap entity=\(value.entity.name) accepted=true"
                )
                toggleControlsFromSpatialSurface(.spatialTap)
            }
    }

    private func toggleControlsFromSpatialSurface(
        _ source: PlaybackSurfaceInputAction.Source
    ) {
        withAnimation(.easeInOut(duration: 0.25)) {
            PlaybackSurfaceInputAction.perform(source, appModel: appModel)
        }
        appModel.recordSurfaceInputProbe(
            "toggle source=\(source) showControls=\(appModel.showControls)"
        )
    }

    // The player-controls window tracks showControls itself so every setter
    // (pinch, accessibility, the test channel) presents identically.
    private func synchronizeControlsWindow(visible: Bool) {
        // Scene operations serialize with presentation transitions: a
        // dismissWindow landing while the immersive scene is still
        // classifying its video component kills the pending RealityKit mode
        // grant (paired probes, 2026-08-10). The transition-end observer
        // replays this sync once the transition settles or rolls back.
        guard appModel.presentationTransition == nil else {
            appModel.recordSurfaceInputProbe(
                "controlsWindow sync deferred visible=\(visible)"
            )
            return
        }
        if visible {
            let identity = appModel.beginFreshPlayerControlsScene()
            openWindow(id: "playerControls", value: identity)
            appModel.recordSurfaceInputProbe("controlsWindow open")
        } else if let identity = appModel.activePlayerControlsSceneIdentity {
            dismissWindow(id: "playerControls", value: identity)
            appModel.recordSurfaceInputProbe("controlsWindow dismiss")
        }
    }

    @MainActor
    private func update(
        _ content: RealityViewContent,
        revision: Int,
        dockedPlacement: PlaybackSurfaceTransform
    ) {
        _ = revision
        playbackVideoEntityStore.synchronizeRealityKitContentTypeScope(
            realityKitContentTypeScope
        )
        updateWorld(in: content)
        let presentation = requestedPresentation
        if presentation == .panorama {
            PlaybackPanoramaInteractionSurface.configure(
                panoramaInteractionSurface,
                projection: playbackRuntime.effectiveProjectionType,
                horizontalFieldOfViewDegrees:
                    playbackRuntime.effectiveHorizontalFieldOfViewDegrees
            )
        }
        updatePanoramaInteractionSurface(
            in: content,
            isActive: presentation == .panorama
        )
        guard presentation.usesImmersiveSpace else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("inactive")
            removeVideo(from: content, reason: "mainWindowPresentation")
            return
        }
        guard let renderer = playbackRuntime.renderer else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererUnavailable")
            removeVideo(from: content, reason: "rendererUnavailable")
            return
        }
        guard presentation != .docked || world.playbackSurfaceAnchor != nil else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForDockedAnchor")
            return
        }

        appModel.recordSpatialPlaybackSurfacePreparationStage("preparingEntity")
        presentVideo(
            in: content,
            with: renderer,
            as: presentation,
            dockedPlacement: dockedPlacement
        )
    }

    @MainActor
    private func updatePanoramaInteractionSurface(
        in content: RealityViewContent,
        isActive: Bool
    ) {
        if isActive {
            if Self.collisionShellInputShelved {
                if hasRecordedCollisionShellShelved == false {
                    hasRecordedCollisionShellShelved = true
                    appModel.recordSurfaceInputProbe("shellShelved")
                }
            } else {
                panoramaInteractionSurface.position = .zero
                panoramaInteractionSurface.orientation = .init()
                if content.entities.contains(where: { $0 === panoramaInteractionSurface }) == false {
                    content.add(panoramaInteractionSurface)
                    appModel.recordSurfaceInputProbe(
                        "shellAttached name=\(panoramaInteractionSurface.name)"
                            + " children=\(panoramaInteractionSurface.children.count)"
                            + " active=\(panoramaInteractionSurface.isActive)"
                    )
                }
            }
            if content.entities.contains(where: { $0 === headInputProbe }) == false {
                content.add(headInputProbe)
                appModel.recordSurfaceInputProbe(
                    "headProbeAttached active=\(headInputProbe.isActive)"
                )
            }
        } else {
            if content.entities.contains(where: { $0 === panoramaInteractionSurface }) {
                content.remove(panoramaInteractionSurface)
                appModel.recordSurfaceInputProbe("shellDetached")
            }
            if content.entities.contains(where: { $0 === headInputProbe }) {
                content.remove(headInputProbe)
            }
        }
    }

    @MainActor
    private func updateWorld(in content: RealityViewContent) {
        guard needsWorld else {
            if let entity = world.entity { content.remove(entity) }
            if let anchor = world.playbackSurfaceAnchor { content.remove(anchor) }
            world.entity = nil
            world.playbackSurfaceAnchor = nil
            world.appliedEnvironment = nil
            world.appliedEnvironmentEffect = nil
            world.hasFailed = false
            appModel.clearEnvironmentSceneEffectObservation()
            return
        }

        if let entity = world.entity {
            applyRequestedEnvironmentAppearance(to: entity)
            if content.entities.contains(where: { $0 === entity }) == false {
                content.add(entity)
            }
            if let anchor = world.playbackSurfaceAnchor,
               content.entities.contains(where: { $0 === anchor }) == false {
                content.add(anchor)
            }
            recordSkyboxActivity(in: entity)
        } else if world.isLoading == false, world.hasFailed == false {
            Task {
                await loadWorld(into: content)
            }
        }
    }

    @MainActor
    private func presentVideo(
        in content: RealityViewContent,
        with renderer: AVSampleBufferVideoRenderer,
        as presentation: PlaybackPresentation,
        dockedPlacement: PlaybackSurfaceTransform
    ) {
        let videoComponentRevision = playbackRuntime.videoComponentRevision
        guard PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
            for: presentation,
            previousPresentation: appModel.presentationTransition?.previousPresentation,
            targetPresentation: appModel.presentationTransition?.targetPresentation,
            sourceRendererMayRelease: appModel.presentationSourceRendererMayRelease,
            targetRendererMayBind: appModel.presentationTargetRendererMayBind
        ) else {
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                "waitingForSourceRendererRelease"
            )
            logSpatialSurfaceReadiness(reason: "waitingForSourceRendererRelease")
            return
        }
        if let rendererConsumerPresentation = playbackRuntime.rendererConsumerPresentation,
           rendererConsumerPresentation.usesMainWindow {
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                "waitingForSourceRendererOwnershipToClear"
            )
            logSpatialSurfaceReadiness(reason: "waitingForSourceRendererOwnershipToClear")
            return
        }
        if playbackVideoEntityStore.hasApplied(
            videoComponentRevision: videoComponentRevision,
            to: renderer,
            presentation: presentation
        ) == false {
            surfaceActivation.cancel()
            rendererTargetObservation.cancel()
            presentationObservation.prepareForReplacementEntity()
        }
        _ = playbackVideoEntityStore.entity(
            for: renderer,
            presentation: presentation,
            videoComponentRevision: videoComponentRevision
        )
        let entity = videoEntity
        entity.name = "EnchronVideo.\(presentation)"
        PlaybackRealityPresenter.setOpacity(
            of: entity,
            to: Float(spatialPresentationOpacity),
            animated: entity.components[OpacityComponent.self] != nil
        )
        surfaceActivation.observe(entity, in: content) {
            if videoEntity.isActive,
               videoEntity.components[VideoPlayerComponent.self] == nil {
                surfaceRefreshTick &+= 1
            }
            attachSpatialSurfaceIfReady()
        }
        if presentation == .docked {
            guard let anchor = world.playbackSurfaceAnchor else { return }
            positionDockedVideo(
                entity,
                relativeTo: anchor,
                transform: dockedPlacement
            )
        } else {
            entity.removeFromParent()
            entity.position = .zero
            entity.orientation = .init()
            entity.scale = .one
            if content.entities.contains(where: { $0 === entity }) == false {
                content.add(entity)
            }
        }
        // RealityKit activates an entity asynchronously after its world anchor
        // enters the scene. Install the target renderer component while that
        // activation is pending; attachSpatialSurfaceIfReady still requires the
        // entity and renderer target to be active before publishing attachment.
        do {
            try playbackRuntime.claimRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation)
            )
        } catch PlaybackRuntime.RuntimeError.rendererConsumerBusy {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererConsumerBusy")
            logSpatialSurfaceReadiness(reason: "rendererConsumerBusy")
            return
        } catch PlaybackRuntime.RuntimeError.rendererTransferPending {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererTransferPending")
            logSpatialSurfaceReadiness(reason: "rendererTransferPending")
            return
        } catch {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererConsumerFailed")
            playbackRuntime.lastErrorMessage = error.localizedDescription
            logSpatialSurfaceReadiness(reason: "rendererConsumerFailed")
            return
        }
        appModel.recordSpatialPlaybackSurfacePreparationStage("rendererConsumerClaimed")
        rendererTargetObservation.observe(
            entity,
            videoComponentRevision: videoComponentRevision,
            in: content
        ) {
            attachSpatialSurfaceIfReady()
        }
        presentationObservation.observe(
            entity,
            in: content,
            contentTypeSessionID: realityKitContentTypeScope?.technicalSessionID,
            onChange: {
                recordSpatialPresentationState()
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
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: presentation,
            requestsSpatialVideoMode: playbackRuntime.requestsSpatialVideoMode
        )
        appModel.recordSpatialPlaybackSurfacePreparationStage("componentConfigured")
        surfaceAccessibilityActivation.observe(entity, in: content) {
            toggleControlsFromSpatialSurface(.accessibilityActivate)
        }
        subtitleSurface.update(
            on: entity,
            presentation: presentation,
            screenSize: entity.components[VideoPlayerComponent.self]?.playerScreenSize ?? .zero,
            reservedBottomFraction: 0,
            frame: playbackRuntime.activeSubtitleFrame
        )
        attachSpatialSurfaceIfReady()
    }

    @MainActor
    private func attachSpatialSurfaceIfReady() {
        let presentation = requestedPresentation
        let renderer = playbackRuntime.renderer
        let componentIsBound = renderer.map {
            PlaybackRealityPresenter.isBound(
                videoEntity,
                to: $0,
                presentation: presentation
            )
        } ?? false
        logSpatialSurfaceReadiness(reason: "attachCheck")
        guard presentation.usesImmersiveSpace else { return }
        // Mirror of the window surface's ownership rule: the runtime
        // attachment belongs to the transition's target presentation, so a
        // departing immersive surface must not re-attach over the returning
        // window surface.
        let owningPresentation =
            appModel.presentationTransition?.targetPresentation
                ?? appModel.playbackPresentation
        guard owningPresentation == presentation else { return }
        guard videoEntity.isActive else {
            let parent = videoEntity.parent
            appModel.recordSpatialPlaybackSurfacePreparationStage(
                [
                    "entityInactive",
                    "entityEnabled=\(videoEntity.isEnabled)",
                    "parent=\(parent?.name ?? "none")",
                    "parentEnabled=\(parent?.isEnabled.description ?? "none")",
                    "parentActive=\(parent?.isActive.description ?? "none")",
                    "worldEnabled=\(world.entity?.isEnabled.description ?? "none")",
                    "worldActive=\(world.entity?.isActive.description ?? "none")",
                ].joined(separator: ",")
            )
            return
        }
        guard renderer != nil else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("rendererUnavailable")
            return
        }
        guard componentIsBound else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForComponentBinding")
            return
        }
        guard rendererTargetObservation.targetIsAvailable else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForRendererTarget")
            return
        }
        guard playbackRuntime.rendererConsumerEntityID
                == entityID(for: presentation) else {
            appModel.recordSpatialPlaybackSurfacePreparationStage("waitingForConsumerClaim")
            return
        }
        appModel.recordSpatialPlaybackSurfacePreparationStage("attachingSurface")
        playbackRuntime.videoRendererTargetDidBind(
            revision: playbackRuntime.videoComponentRevision,
            entityID: entityID(for: presentation)
        )
        if let component = videoEntity.components[VideoPlayerComponent.self] {
            // On visionOS 27, moving this entity between RealityView scenes can
            // leave the previous current mode in place while the requested mode
            // remains unchanged. Reapply the request for a bounded interval after
            // activation so RealityKit can begin the transition in the new scene.
            let recoveryAction = presentationObservation.modeRecoveryAction(
                to: videoEntity,
                presentation: presentation,
                component: component,
                projection: playbackRuntime.effectiveProjectionType,
                sourceContentKind: playbackRuntime.sourceVideoContentKind,
                provenance: playbackRuntime.activeMediaFormatProvenance,
                observedContentType:
                    playbackVideoEntityStore.realityKitContentType
            )
            switch recoveryAction {
            case .none:
                break
            case .requestModesAgain:
                appModel.recordSurfaceInputProbe(
                    "modeRequestRetry presentation=\(presentation)"
                )
                PlaybackRealityPresenter.reapplyDesiredModesAfterSceneActivation(
                    videoEntity,
                    presentation: presentation,
                    requestsSpatialVideoMode: playbackRuntime.requestsSpatialVideoMode
                )
            }
        }
        do {
            try playbackRuntime.attach(
                entityID: entityID(for: presentation),
                realityViewID: realityViewID(for: presentation),
                presentation: presentation
            )
            appModel.recordSpatialPlaybackSurfacePreparationStage("surfaceAttached")
            recordSpatialPresentationState()
        } catch {
            appModel.recordSpatialPlaybackSurfacePreparationStage("surfaceAttachFailed")
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    private func logSpatialSurfaceReadiness(reason: String) {
        let presentation = requestedPresentation
        let renderer = playbackRuntime.renderer
        let component = videoEntity.components[VideoPlayerComponent.self]
        let componentIsBound = renderer.map {
            component?.videoRenderer === $0
        } ?? false
        let signature = [
            presentation.rawValue,
            String(describing: ObjectIdentifier(videoEntity)),
            videoEntity.isActive ? "active" : "inactive",
            renderer == nil ? "rendererMissing" : "rendererAvailable",
            componentIsBound ? "componentBound" : "componentUnbound",
            rendererTargetObservation.targetIsAvailable
                ? "targetAvailable"
                : "targetUnavailable",
            playbackRuntime.rendererConsumerEntityID == entityID(for: presentation)
                ? "consumerClaimed"
                : "consumerUnclaimed",
            playbackRuntime.attachedPresentation == presentation
                ? "runtimeAttached"
                : "runtimeDetached",
            "componentRevision=\(playbackRuntime.videoComponentRevision)",
            "boundRevision=\(playbackRuntime.boundVideoComponentRevision.map(String.init) ?? "none")",
            "contentType=\(playbackVideoEntityStore.realityKitContentType)",
            "desiredImmersiveMode=\(String(describing: component?.desiredImmersiveViewingMode))",
            "actualImmersiveMode=\(String(describing: component?.immersiveViewingMode))",
            "desiredViewingMode=\(String(describing: component?.desiredViewingMode))",
            "actualViewingMode=\(String(describing: component?.viewingMode))",
            "rendering=\(String(describing: component?.currentRenderingStatus))"
        ].joined(separator: "|")
        guard presentationObservation.shouldLogSurfaceReadiness(
            reason: reason,
            signature: signature
        ) else { return }
        logger.notice(
            "spatial surface facts \(reason, privacy: .public)|\(signature, privacy: .public)"
        )
    }

    @MainActor
    private func recordSpatialPresentationState() {
        let presentation = requestedPresentation
        let realityViewID = realityViewID(for: presentation)
        guard presentation.usesImmersiveSpace,
              videoEntity.isActive,
              rendererTargetObservation.targetIsAvailable,
              playbackRuntime.rendererConsumerEntityID
                == entityID(for: presentation),
              playbackRuntime.attachedPresentation == presentation,
              let renderer = playbackRuntime.renderer,
              PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: presentation
              ),
              let component = videoEntity.components[VideoPlayerComponent.self] else {
            return
        }
        let parentID = videoEntity.parent.map { String(describing: ObjectIdentifier($0)) }
        let immersiveModeIsSettled = presentation != .panorama
            || SpatialPlaybackSurfaceSettlementPolicy.immersiveViewingModeMatches(
                contentIsPanoramic: playbackRuntime.effectiveContentIsPanoramic,
                requiresTransitionConfirmation: true,
                desiredImmersiveViewingMode: String(
                    describing: component.desiredImmersiveViewingMode
                ),
                observedImmersiveViewingMode: component.immersiveViewingMode.map {
                    String(describing: $0)
                }
            )
        let contentTypeMatchesProjection = presentation != .panorama
            || SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: playbackRuntime.effectiveProjectionType,
                sourceContentKind: playbackRuntime.sourceVideoContentKind,
                provenance: playbackRuntime.activeMediaFormatProvenance,
                observedContentType: playbackVideoEntityStore.realityKitContentType
            )
        let displayedPixelBuffer = playbackRuntime.renderer?.displayedPixelBuffer() != nil
        let viewingModeMatches =
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                observedViewingMode: component.viewingMode.map {
                    String(describing: $0)
                },
                requiresObservedMode: presentation == .panorama
            )
        let explicitOverrideAdoptionIsConfirmed = presentation == .panorama
            && SpatialPlaybackSurfaceSettlementPolicy
                .explicitOverrideAdoptionIsConfirmed(
                    projection: playbackRuntime.effectiveProjectionType,
                    stereoLayout: playbackRuntime.effectiveStereoLayout,
                    provenance: playbackRuntime.activeMediaFormatProvenance,
                    acceptedRendererProjectionKind:
                        playbackRuntime.acceptedRendererProjectionKind,
                    desiredImmersiveViewingMode: String(
                        describing: component.desiredImmersiveViewingMode
                    ),
                    observedImmersiveViewingMode:
                        component.immersiveViewingMode.map {
                            String(describing: $0)
                        },
                    observedViewingMode: component.viewingMode.map {
                        String(describing: $0)
                    }
                )
        let isSettled = component.currentRenderingStatus == .ready
            && immersiveModeIsSettled
            && (contentTypeMatchesProjection
                || explicitOverrideAdoptionIsConfirmed)
            && viewingModeMatches
            && component.spatialVideoMode == component.desiredSpatialVideoMode
            && displayedPixelBuffer
        let settlementBreakdown = [
            "settled=\(isSettled)",
            "ready=\(component.currentRenderingStatus == .ready)",
            "immersiveMode=\(immersiveModeIsSettled)",
            "contentTypeMatches=\(contentTypeMatchesProjection)",
            "overrideAdopted=\(explicitOverrideAdoptionIsConfirmed)",
            "viewingMode=\(viewingModeMatches)",
            "spatialMode=\(component.spatialVideoMode == component.desiredSpatialVideoMode)",
            "pixels=\(displayedPixelBuffer)",
            "rkContentType=\(playbackVideoEntityStore.realityKitContentType)",
            "provenance=\(playbackRuntime.activeMediaFormatProvenance.rawValue)",
            "acceptedProjection=\(String(describing: playbackRuntime.acceptedRendererProjectionKind))",
            "status=\(String(describing: component.currentRenderingStatus))",
            "wantImmersive=\(String(describing: component.desiredImmersiveViewingMode))",
            "gotImmersive=\(component.immersiveViewingMode.map { String(describing: $0) } ?? "none")",
            "wantViewing=\(String(describing: component.desiredViewingMode))",
            "gotViewing=\(component.viewingMode.map { String(describing: $0) } ?? "none")",
            "stereoLayout=\(playbackRuntime.effectiveStereoLayout.rawValue)",
            "componentBound=\(playbackRuntime.renderer.map { component.videoRenderer === $0 } ?? false)",
            "technicalSession=\(playbackRuntime.activeTechnicalSessionID ?? "none")",
            "retiring=\(playbackRuntime.retiringTechnicalSessionCount)",
        ].joined(separator: ",")
        if presentationObservation.shouldLogSurfaceReadiness(
            reason: "settlement",
            signature: settlementBreakdown
        ) {
            appModel.recordSurfaceInputProbe("settlement \(settlementBreakdown)")
        }
        recordSpatialPlaybackSurfaceObservation(
            presentation: presentation,
            component: component,
            settled: isSettled
        )
        playbackRuntime.recordPresentationState(
            presentation: presentation,
            phase: isSettled ? .settled : .surfaceAttached,
            entityID: entityID(for: presentation),
            videoComponentRevision: playbackRuntime.videoComponentRevision,
            realityViewID: realityViewID,
            entityParentID: parentID,
            desiredImmersiveViewingMode: String(describing: component.desiredImmersiveViewingMode),
            actualImmersiveViewingMode: component.immersiveViewingMode.map { String(describing: $0) },
            desiredViewingMode: String(describing: component.desiredViewingMode),
            actualViewingMode: component.viewingMode.map { String(describing: $0) },
            desiredSpatialVideoMode: String(describing: component.desiredSpatialVideoMode),
            actualSpatialVideoMode: String(describing: component.spatialVideoMode),
            componentRenderingStatus: String(describing: component.currentRenderingStatus),
            displayedPixelBuffer: displayedPixelBuffer
        )
    }

    @MainActor
    private func recordSpatialPlaybackSurfaceObservation(
        presentation: PlaybackPresentation,
        component: VideoPlayerComponent,
        settled: Bool
    ) {
        let worldPosition = videoEntity.position(relativeTo: nil)
        let worldOrientation = videoEntity.orientation(relativeTo: nil)
        let worldScale = videoEntity.scale(relativeTo: nil)
        let worldDistance = simd_length(worldPosition)
        let worldElevationDegrees: Float
        let forwardToUserDot: Float
        if worldDistance > 0.0001 {
            worldElevationDegrees = asin(
                min(max(worldPosition.y / worldDistance, -1), 1)
            ) * 180 / .pi
            let entityForward = simd_normalize(
                worldOrientation.act(SIMD3<Float>(0, 0, -1))
            )
            forwardToUserDot = simd_dot(
                entityForward,
                simd_normalize(-worldPosition)
            )
        } else {
            worldElevationDegrees = 0
            forwardToUserDot = 0
        }
        let playerScreenSize = component.playerScreenSize
        appModel.recordSpatialPlaybackSurfaceObservation(
            SpatialPlaybackSurfaceObservation(
                presentation: presentation.rawValue,
                parentName: videoEntity.parent?.name ?? "none",
                anchorMatched: presentation != .docked
                    || videoEntity.parent === world.playbackSurfaceAnchor,
                localPosition: videoEntity.position,
                worldPosition: worldPosition,
                localScale: videoEntity.scale,
                worldScale: worldScale,
                worldDistance: worldDistance,
                worldElevationDegrees: worldElevationDegrees,
                forwardToUserDot: forwardToUserDot,
                playerScreenSize: playerScreenSize,
                renderedSize: SIMD2<Float>(
                    playerScreenSize.x * videoEntity.scale.x,
                    playerScreenSize.y * videoEntity.scale.y
                ),
                renderingReady: component.currentRenderingStatus == .ready,
                surfaceOpacity: videoEntity.components[OpacityComponent.self]?.opacity ?? 1,
                contentType: playbackVideoEntityStore.realityKitContentType,
                desiredImmersiveViewingMode: String(
                    describing: component.desiredImmersiveViewingMode
                ),
                actualImmersiveViewingMode: component.immersiveViewingMode.map {
                    String(describing: $0)
                } ?? "none",
                desiredViewingMode: String(describing: component.desiredViewingMode),
                actualViewingMode: component.viewingMode.map {
                    String(describing: $0)
                } ?? "none",
                desiredSpatialVideoMode: String(
                    describing: component.desiredSpatialVideoMode
                ),
                actualSpatialVideoMode: String(describing: component.spatialVideoMode),
                settled: settled
            )
        )
    }

    @MainActor
    private func loadWorld(into content: RealityViewContent) async {
        guard world.entity == nil, world.isLoading == false, world.hasFailed == false else { return }
        world.isLoading = true
        appModel.recordSpatialPlaybackSurfacePreparationStage("loadingWorld")
        defer { world.isLoading = false }
        logger.notice("world load started")
        do {
            let entity = try await Entity(named: "world")
            let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: entity)
            let anchorWorldTransform = anchor.transformMatrix(relativeTo: nil)
            guard applyRequestedEnvironmentAppearance(to: entity) else {
                throw EnvironmentSceneEffectError.skyboxMissing
            }
            // RealityKit does not activate the empty transform marker when it
            // remains inside this compiled environment resource. Keep the
            // marker's stable identity and authored world transform, but make
            // it a live RealityView root so its playback child can activate.
            anchor.removeFromParent()
            content.add(entity)
            content.add(anchor)
            anchor.setTransformMatrix(anchorWorldTransform, relativeTo: nil)
            world.entity = entity
            world.playbackSurfaceAnchor = anchor
            appModel.recordSpatialPlaybackSurfacePreparationStage("worldReady")
            recordSkyboxActivity(in: entity)
            logger.notice("world load completed")
            update(
                content,
                revision: surfaceRefreshTick,
                dockedPlacement: currentDockedSurfaceTransform
            )
        } catch {
            world.hasFailed = true
            appModel.recordSpatialPlaybackSurfacePreparationStage("worldLoadFailed")
            logger.error("world load failed error=\(error.localizedDescription, privacy: .public)")
            playbackRuntime.lastErrorMessage = "Failed to load the selected environment: \(error.localizedDescription)"
        }
    }

    @MainActor
    @discardableResult
    private func applyRequestedEnvironmentAppearance(to entity: Entity) -> Bool {
        guard let environment = requestedEnvironmentContext.environment else {
            EnvironmentSceneAppearanceApplier.clear(in: entity)
            world.appliedEnvironment = nil
            world.appliedEnvironmentEffect = nil
            appModel.clearEnvironmentSceneEffectObservation()
            return true
        }
        let effect = requestedEnvironmentContext.effect
        if world.appliedEnvironment == environment,
           world.appliedEnvironmentEffect == effect,
           appModel.environmentSkyboxOpacity != nil {
            return true
        }
        guard let opacity = EnvironmentSceneAppearanceApplier.apply(
            environment: environment,
            effect: effect,
            to: entity
        ) else {
            return false
        }
        world.appliedEnvironment = environment
        world.appliedEnvironmentEffect = effect
        appModel.recordEnvironmentSceneEffect(opacity: opacity)
        return true
    }

    @MainActor
    private func recordSkyboxActivity(in entity: Entity) {
        appModel.recordEnvironmentSkyboxIsActive(
            entity.findEntity(named: EnvironmentSceneAppearanceApplier.skyboxName)?.isActive == true
                || entity.findEntity(
                    named: EnvironmentSceneAppearanceApplier.scenicPlaceholderName
                )?.isActive == true
        )
    }

    @MainActor
    private func removeVideo(from content: RealityViewContent, reason: String) {
        let consumerPresentation = playbackRuntime.rendererConsumerPresentation
        let attachedPresentation = playbackRuntime.attachedPresentation
        let ownsSpatialConsumer = consumerPresentation?.usesImmersiveSpace == true
        let ownsSpatialAttachment = attachedPresentation?.usesImmersiveSpace == true
        guard ownsSpatialConsumer || ownsSpatialAttachment else { return }

        logger.notice("video surface removed reason=\(reason, privacy: .public)")
        if preservesDepartingSpatialSurfaceForFade {
            releaseSpatialRendererOwnershipWhileKeepingVisibleSurface()
            return
        }
        if let consumerPresentation,
           consumerPresentation.usesImmersiveSpace,
           playbackRuntime.rendererConsumerEntityID == entityID(for: consumerPresentation) {
            content.remove(videoEntity)
        }
        releaseSpatialSurface()
    }

    @MainActor
    private func releaseSpatialSurface() {
        let presentation = playbackRuntime.rendererConsumerPresentation
            ?? playbackRuntime.attachedPresentation
        subtitleSurface.remove()
        surfaceActivation.cancel()
        surfaceAccessibilityActivation.cancel()
        rendererTargetObservation.cancel()
        presentationObservation.cancel()
        appModel.clearSpatialPlaybackSurfaceObservation()
        panoramaInteractionSurface.removeFromParent()
        headInputProbe.removeFromParent()
        guard let presentation, presentation.usesImmersiveSpace else { return }
        videoEntity.removeFromParent()
        let preservesPlaybackComponent = playbackRuntime.activeSessionID != nil
        if preservesPlaybackComponent == false {
            playbackVideoEntityStore.releasePlaybackComponent()
        }
        if playbackRuntime.rendererConsumerEntityID == entityID(for: presentation) {
            playbackRuntime.releaseRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation),
                preservingVideoComponent: preservesPlaybackComponent
            )
        }
        detachSpatialSurface()
    }

    private var preservesDepartingSpatialSurfaceForFade: Bool {
        guard let transition = appModel.presentationTransition else {
            return false
        }
        return transition.previousPresentation.usesImmersiveSpace
            && transition.targetPresentation.usesMainWindow
            && appModel.presentationSourceRendererMayRelease
    }

    private func releaseSpatialRendererOwnershipWhileKeepingVisibleSurface() {
        let sourcePresentation = appModel.presentationTransition?
            .previousPresentation
        surfaceActivation.cancel()
        surfaceAccessibilityActivation.cancel()
        rendererTargetObservation.cancel()
        presentationObservation.cancel()
        subtitleSurface.remove()
        guard let sourcePresentation,
              playbackRuntime.rendererConsumerEntityID
                == entityID(for: sourcePresentation) else {
            return
        }
        playbackVideoEntityStore.releasePlaybackComponentForRealityViewTransfer()
        playbackRuntime.releaseRendererConsumer(
            presentation: sourcePresentation,
            entityID: entityID(for: sourcePresentation),
            preservingVideoComponent: false
        )
        playbackRuntime.detachSurface(
            entityID: entityID(for: sourcePresentation),
            realityViewID: realityViewID(for: sourcePresentation)
        )
    }

    private var spatialSurfaceReadinessKey: String {
        let presentation = requestedPresentation
        let rendererID = playbackRuntime.renderer.map {
            String(describing: ObjectIdentifier($0))
        } ?? "rendererNone"
        return [
            presentation.rawValue,
            realityKitContentTypeScope?.sessionID ?? "sessionNone",
            playbackRuntime.activeMediaFormatProvenance.rawValue,
            playbackRuntime.sourceVideoContentKind.rawValue,
            playbackRuntime.effectiveProjectionType.rawValue,
            String(playbackRuntime.effectiveHorizontalFieldOfViewDegrees),
            playbackRuntime.effectiveStereoLayout.rawValue,
            playbackRuntime.effectiveVideoFormatRevision.map(String.init)
                ?? "formatRevisionNone",
            rendererID,
            String(playbackRuntime.videoComponentRevision),
            playbackRuntime.rendererConsumerEntityID ?? "consumerNone",
            playbackRuntime.attachedPresentation?.rawValue ?? "attachedNone",
            playbackRuntime.hasActivePlaybackRequest ? "requestActive" : "requestNone",
            playbackRuntime.productLifecycle.rawValue,
            appModel.presentationSourceRendererMayRelease
                ? "sourceMayRelease"
                : "sourceMustRemain",
            appModel.presentationTargetRendererMayBind
                ? "targetMayBind"
                : "targetMustWait"
        ].joined(separator: "|")
    }

    @MainActor
    private func retrySpatialSurfaceAttachment() async {
        while spatialSurfaceAttachmentCanStillSettle {
            guard Task.isCancelled == false else { return }
            if appModel.spatialPlaybackSurfaceObservation.settled,
               playbackRuntime.attachedPresentation == requestedPresentation,
               playbackRuntime.rendererConsumerEntityID
                    == entityID(for: requestedPresentation) {
                return
            }
            surfaceRefreshTick &+= 1
            surfaceActivation.requestRetry()
            try? await Task.sleep(for: PlaybackSurfaceActivation.retryIntervalForView)
        }
    }

    /// An opened Immersive Space keeps driving its idempotent attach path
    /// while the requested media session is viable. High-resolution startup
    /// latency is not evidence that RealityKit rejected the target surface.
    private var spatialSurfaceAttachmentCanStillSettle: Bool {
        guard requestedPresentation.usesImmersiveSpace,
              playbackRuntime.hasActivePlaybackRequest else {
            return false
        }
        switch playbackRuntime.productLifecycle {
        case .loading, .ready, .playing, .paused, .ended:
            return true
        case .idle, .failed:
            return false
        }
    }

    private func entityID(for presentation: PlaybackPresentation) -> String {
        playbackVideoEntityStore.hostedEntityID(
            for: presentation,
            during: appModel.presentationTransition
        )
    }

    private func realityViewID(for presentation: PlaybackPresentation) -> String {
        _ = presentation
        return "EnchronRealityView.spatial#\(ObjectIdentifier(videoEntity))"
    }

    private func detachSpatialSurface() {
        guard let presentation = playbackRuntime.attachedPresentation,
              presentation.usesImmersiveSpace else { return }
        playbackRuntime.detachSurface(
            entityID: entityID(for: presentation),
            realityViewID: realityViewID(for: presentation)
        )
    }

    private func positionDockedVideo(
        _ entity: Entity,
        relativeTo anchor: Entity,
        transform: PlaybackSurfaceTransform
    ) {
        PlaybackSurfacePlacement.dock(
            entity,
            to: anchor,
            transform: transform
        )
    }
}

private enum EnvironmentSceneEffectError: LocalizedError {
    case skyboxMissing

    var errorDescription: String? {
        "The environment resource does not contain its skybox entity."
    }
}
