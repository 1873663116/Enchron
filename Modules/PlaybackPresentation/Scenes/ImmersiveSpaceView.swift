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
    static let daySkyboxOpacity: Float = 1
    static let nightSkyboxOpacity: Float = 0.35

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
        case .day: daySkyboxOpacity
        case .night: nightSkyboxOpacity
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
        let brightness: CGFloat = effect == .day ? 1 : 0.46
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
    private var subscriptions: [EventSubscription] = []
    private let modeRequestRetry = PlaybackModeRequestRetry()
    private(set) var contentType = "unobserved"
    private var panoramaTargetBootstrapState: PanoramaTargetBootstrapState =
        .awaitingPortalActivation
    private var lastSurfaceReadinessSignatureByReason: [String: String] = [:]

    func observe(
        _ entity: Entity,
        in content: RealityViewContent,
        onChange: @escaping @MainActor () -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard entityID != nextEntityID else { return }
        cancel()
        entityID = nextEntityID
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
            },
            // ContentTypeDidChange doesn't expose its source entity. This
            // Immersive Space owns one video surface, so subscribe at the
            // RealityView scene boundary as Apple demonstrates for this event.
            content.subscribe(to: VideoPlayerEvents.ContentTypeDidChange.self) {
                [weak self] event in
                let contentType = String(describing: event.contentType)
                Task { @MainActor in
                    self?.contentType = contentType
                    onChange()
                }
            }
        ]
    }

    func cancel() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
        contentType = "unobserved"
        panoramaTargetBootstrapState = .awaitingPortalActivation
        lastSurfaceReadinessSignatureByReason.removeAll()
        modeRequestRetry.reset()
    }

    func requestProgressiveForPanoramaTargetIfReady(
        component: VideoPlayerComponent,
        projection: PlaybackModel.ProjectionType
    ) -> Bool {
        guard panoramaTargetBootstrapState == .awaitingPortalActivation else {
            return false
        }
        let targetHasReadyContent = component.currentRenderingStatus == .ready
            && SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: projection,
                observedContentType: contentType
            )
        let targetReportedPortal = component.immersiveViewingMode.map {
            String(describing: $0).lowercased()
        } == "portal"
        guard targetHasReadyContent || targetReportedPortal else { return false }
        return panoramaTargetBootstrapState.receivePortalActivation()
    }

    func receivePanoramaProgressiveConfirmation(
        component: VideoPlayerComponent
    ) {
        guard component.immersiveViewingMode.map({
            String(describing: $0).lowercased()
        }) == "progressive" else { return }
        panoramaTargetBootstrapState.receiveProgressiveChange()
    }

    var panoramaProgressiveIsConfirmed: Bool {
        panoramaTargetBootstrapState == .progressiveConfirmed
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
        component: VideoPlayerComponent
    ) -> PlaybackModeRecoveryAction {
        modeRequestRetry.recoveryAction(
            entity: entity,
            presentation: presentation,
            desiredViewingMode: String(describing: component.desiredViewingMode),
            actualViewingMode: component.viewingMode.map { String(describing: $0) },
            desiredImmersiveViewingMode: String(
                describing: component.desiredImmersiveViewingMode
            ),
            actualImmersiveViewingMode: component.immersiveViewingMode.map {
                String(describing: $0)
            }
        )
    }
}

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    @State private var world = WorldSceneState()
    @State private var playbackVideoEntityStore = PlaybackVideoEntityStore()
    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var realityViewUpdateScheduler = PlaybackRealityViewUpdateScheduler()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var surfaceAccessibilityActivation =
        PlaybackSurfaceAccessibilityActivationObservation()
    @State private var rendererTargetObservation =
        PlaybackVideoRendererTargetObservation()
    @State private var presentationObservation = SpatialPresentationObservation()
    @State private var surfaceRefreshTick = 0
    private let logger = Logger(subsystem: "app.enchron", category: "SpatialSurface")

    private var videoEntity: Entity {
        playbackVideoEntityStore.entity
    }

    public init() {}

    private var requestedPresentation: PlaybackPresentation {
        guard let transition = appModel.presentationTransition else {
            return appModel.playbackPresentation
        }
        if transition.targetPresentation == .window,
           appModel.presentationSourceRendererMayRelease == false {
            return transition.previousPresentation
        }
        return transition.targetPresentation
    }

    private var requestedEnvironmentContext: EnvironmentContext {
        guard let transition = appModel.presentationTransition else {
            return appModel.environmentContext
        }
        if transition.targetPresentation == .window,
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
        .realityScripting()
        .gesture(spatialSurfaceTapGesture)
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
    }

    private func scheduleSpatialSurfaceUpdate(_ content: RealityViewContent) {
        let revision = surfaceRefreshTick
        realityViewUpdateScheduler.schedule {
            if needsWorld {
                await loadWorld(into: content)
            }
            update(content, revision: revision)
        }
    }

    private var needsWorld: Bool {
        requestedPresentation == .docked
            || (requestedPresentation == .window
                && requestedEnvironmentContext.environment != nil)
    }

    private var spatialPresentationOpacity: Double {
        PlaybackPresentationTransitionAppearance.opacity(
            for: requestedPresentation,
            settledPresentation: appModel.playbackPresentation,
            transition: appModel.presentationTransition
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
            .targetedToEntity(videoEntity)
            .onEnded { _ in
                toggleControlsFromSpatialSurface(.spatialTap)
            }
    }

    private func toggleControlsFromSpatialSurface(
        _ source: PlaybackSurfaceInputAction.Source
    ) {
        withAnimation(.easeInOut(duration: 0.25)) {
            PlaybackSurfaceInputAction.perform(source, appModel: appModel)
        }
    }

    @MainActor
    private func update(_ content: RealityViewContent, revision: Int) {
        _ = revision
        updateWorld(in: content)
        let presentation = requestedPresentation
        guard presentation != .window else {
            removeVideo(from: content, reason: "windowPresentation")
            return
        }
        guard let renderer = playbackRuntime.renderer else {
            removeVideo(from: content, reason: "rendererUnavailable")
            return
        }
        guard presentation != .docked || world.playbackSurfaceAnchor != nil else { return }

        presentVideo(in: content, with: renderer, as: presentation)
    }

    @MainActor
    private func updateWorld(in content: RealityViewContent) {
        guard needsWorld else {
            if let entity = world.entity { content.remove(entity) }
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
            recordSkyboxActivity(in: entity)
        } else if world.isLoading == false, world.hasFailed == false {
            Task { await loadWorld(into: content) }
        }
    }

    @MainActor
    private func presentVideo(
        in content: RealityViewContent,
        with renderer: AVSampleBufferVideoRenderer,
        as presentation: PlaybackPresentation
    ) {
        let videoComponentRevision = playbackRuntime.videoComponentRevision
        if playbackVideoEntityStore.hasApplied(
            videoComponentRevision: videoComponentRevision,
            to: renderer
        ) == false {
            surfaceActivation.cancel()
            rendererTargetObservation.cancel()
            presentationObservation.cancel()
        }
        _ = playbackVideoEntityStore.entity(
            for: renderer,
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
            positionDockedVideo(entity, relativeTo: anchor)
        } else {
            entity.removeFromParent()
            entity.position = .zero
            entity.orientation = .init()
            entity.scale = .one
            if content.entities.contains(where: { $0 === entity }) == false {
                content.add(entity)
            }
        }
        guard entity.isActive else {
            logSpatialSurfaceReadiness(reason: "entityInactive")
            return
        }
        guard PlaybackPresentationRendererBindingPolicy.shouldBindRenderer(
            for: presentation,
            previousPresentation: appModel.presentationTransition?.previousPresentation,
            targetPresentation: appModel.presentationTransition?.targetPresentation,
            sourceRendererMayRelease: appModel.presentationSourceRendererMayRelease
        ) else {
            logSpatialSurfaceReadiness(reason: "waitingForSourceRendererRelease")
            return
        }
        do {
            try playbackRuntime.claimRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation)
            )
        } catch PlaybackRuntime.RuntimeError.rendererConsumerBusy {
            logSpatialSurfaceReadiness(reason: "rendererConsumerBusy")
            return
        } catch PlaybackRuntime.RuntimeError.rendererTransferPending {
            logSpatialSurfaceReadiness(reason: "rendererTransferPending")
            return
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
            logSpatialSurfaceReadiness(reason: "rendererConsumerFailed")
            return
        }
        rendererTargetObservation.observe(
            entity,
            videoComponentRevision: videoComponentRevision,
            in: content
        ) {
            attachSpatialSurfaceIfReady()
        }
        presentationObservation.observe(entity, in: content) {
            recordSpatialPresentationState()
        }
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: presentation,
            stereoLayout: playbackRuntime.effectiveStereoLayout,
            panoramaTargetBootstrapPhase: presentation == .panorama
                ? .portal : .progressive
        )
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
        guard presentation != .window,
              videoEntity.isActive,
              renderer != nil,
              componentIsBound,
              rendererTargetObservation.targetIsAvailable,
              playbackRuntime.rendererConsumerEntityID
                == entityID(for: presentation) else { return }
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
                component: component
            )
            switch recoveryAction {
            case .none:
                break
            case .requestModesAgain:
                PlaybackRealityPresenter.reapplyDesiredModesAfterSceneActivation(
                    videoEntity,
                    presentation: presentation,
                    stereoLayout: playbackRuntime.effectiveStereoLayout
                )
            case .replaceRendererGraph:
                Task { @MainActor in
                    do {
                        try await playbackRuntime.recoverRendererGraphAfterPresentationTransfer()
                    } catch {
                        playbackRuntime.lastErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        do {
            try playbackRuntime.attach(
                entityID: entityID(for: presentation),
                realityViewID: realityViewID(for: presentation),
                presentation: presentation
            )
            recordSpatialPresentationState()
        } catch {
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
            "contentType=\(presentationObservation.contentType)",
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
        guard presentation != .window,
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
            || presentationObservation.panoramaProgressiveIsConfirmed
        let contentTypeMatchesProjection = presentation != .panorama
            || SpatialPlaybackSurfaceSettlementPolicy.contentTypeMatches(
                projection: playbackRuntime.effectiveProjectionType,
                observedContentType: presentationObservation.contentType
            )
        let displayedPixelBuffer = playbackRuntime.renderer?.displayedPixelBuffer() != nil
        if presentation == .panorama,
           presentationObservation.requestProgressiveForPanoramaTargetIfReady(
                component: component,
                projection: playbackRuntime.effectiveProjectionType
           ) {
            PlaybackRealityPresenter.reapplyDesiredModesAfterSceneActivation(
                videoEntity,
                presentation: presentation,
                panoramaTargetBootstrapPhase: .progressive,
                stereoLayout: playbackRuntime.effectiveStereoLayout
            )
        }
        if presentation == .panorama {
            presentationObservation.receivePanoramaProgressiveConfirmation(
                component: component
            )
        }
        let viewingModeMatches =
            SpatialPlaybackSurfaceSettlementPolicy.viewingModeMatches(
                stereoLayout: playbackRuntime.effectiveStereoLayout,
                observedViewingMode: component.viewingMode.map {
                    String(describing: $0)
                },
                requiresObservedMode: presentation == .panorama
            )
        let isSettled = component.currentRenderingStatus == .ready
            && immersiveModeIsSettled
            && contentTypeMatchesProjection
            && viewingModeMatches
            && component.spatialVideoMode == component.desiredSpatialVideoMode
            && displayedPixelBuffer
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
                contentType: presentationObservation.contentType,
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
        defer { world.isLoading = false }
        logger.notice("world load started")
        do {
            let entity = try await Entity(named: "world")
            let anchor = try PlaybackSurfaceAnchorResolver.resolve(in: entity)
            guard applyRequestedEnvironmentAppearance(to: entity) else {
                throw EnvironmentSceneEffectError.skyboxMissing
            }
            content.add(entity)
            world.entity = entity
            world.playbackSurfaceAnchor = anchor
            recordSkyboxActivity(in: entity)
            logger.notice("world load completed")
            update(content, revision: surfaceRefreshTick)
        } catch {
            world.hasFailed = true
            logger.error("world load failed error=\(error.localizedDescription, privacy: .public)")
            playbackRuntime.lastErrorMessage = "Failed to load the selected environment: \(error.localizedDescription)"
        }
    }

    @MainActor
    @discardableResult
    private func applyRequestedEnvironmentAppearance(to entity: Entity) -> Bool {
        guard let environment = requestedEnvironmentContext.environment else {
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
        let ownsSpatialConsumer = consumerPresentation.map { $0 != .window } ?? false
        let ownsSpatialAttachment = attachedPresentation.map { $0 != .window } ?? false
        guard ownsSpatialConsumer || ownsSpatialAttachment else { return }

        logger.notice("video surface removed reason=\(reason, privacy: .public)")
        if preservesDepartingSpatialSurfaceForFade {
            releaseSpatialRendererOwnershipWhileKeepingVisibleSurface()
            return
        }
        if let consumerPresentation,
           consumerPresentation != .window,
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
        rendererTargetObservation.cancel()
        presentationObservation.cancel()
        appModel.clearSpatialPlaybackSurfaceObservation()
        videoEntity.removeFromParent()
        PlaybackRealityPresenter.releaseVideoRenderer(from: videoEntity)
        if let presentation,
           presentation != .window,
           playbackRuntime.rendererConsumerEntityID == entityID(for: presentation) {
            playbackRuntime.releaseRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation)
            )
        }
        detachSpatialSurface()
    }

    private var preservesDepartingSpatialSurfaceForFade: Bool {
        guard let transition = appModel.presentationTransition else {
            return false
        }
        return transition.previousPresentation != .window
            && transition.targetPresentation == .window
            && appModel.presentationSourceRendererMayRelease
    }

    private func releaseSpatialRendererOwnershipWhileKeepingVisibleSurface() {
        let sourcePresentation = appModel.presentationTransition?
            .previousPresentation
        surfaceActivation.cancel()
        rendererTargetObservation.cancel()
        presentationObservation.cancel()
        guard let sourcePresentation,
              playbackRuntime.rendererConsumerEntityID
                == entityID(for: sourcePresentation) else {
            return
        }
        playbackRuntime.releaseRendererConsumer(
            presentation: sourcePresentation,
            entityID: entityID(for: sourcePresentation)
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
            playbackRuntime.activeSessionID ?? "sessionNone",
            rendererID,
            String(playbackRuntime.videoComponentRevision),
            playbackRuntime.rendererConsumerEntityID ?? "consumerNone",
            playbackRuntime.attachedPresentation?.rawValue ?? "attachedNone"
        ].joined(separator: "|")
    }

    @MainActor
    private func retrySpatialSurfaceAttachment() async {
        guard requestedPresentation != .window else { return }
        for _ in 0..<PlaybackSurfaceActivation.maximumRetryCountForView {
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

    private func entityID(for presentation: PlaybackPresentation) -> String {
        _ = presentation
        return "EnchronVideo.spatial#\(ObjectIdentifier(videoEntity))"
    }

    private func realityViewID(for presentation: PlaybackPresentation) -> String {
        _ = presentation
        return "EnchronRealityView.spatial#\(ObjectIdentifier(videoEntity))"
    }

    private func detachSpatialSurface() {
        guard let presentation = playbackRuntime.attachedPresentation,
              presentation != .window else { return }
        playbackRuntime.detachSurface(
            entityID: entityID(for: presentation),
            realityViewID: realityViewID(for: presentation)
        )
    }

    private func positionDockedVideo(_ entity: Entity, relativeTo anchor: Entity) {
        PlaybackSurfacePlacement.dock(
            entity,
            to: anchor,
            transform: .init(
                distance: appModel.screenDepthOffset,
                elevationDegrees: appModel.screenViewAngle,
                scale: appModel.screenScale
            )
        )
    }
}

private enum EnvironmentSceneEffectError: LocalizedError {
    case skyboxMissing

    var errorDescription: String? {
        "The environment resource does not contain its skybox entity."
    }
}
