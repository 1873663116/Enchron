import AVFoundation
import OSLog
import PlaybackFeature
import PlaybackPresentation
import RealityKit
import RealityKitScripting
import SwiftUI

@MainActor
private final class WorldSceneState {
    var entity: Entity?
    var playbackSurfaceAnchor: Entity?
    var isLoading = false
    var hasFailed = false
}

@MainActor
private final class SpatialPresentationObservation {
    private var entityID: ObjectIdentifier?
    private var subscriptions: [EventSubscription] = []

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
                Task { @MainActor in onChange() }
            },
            content.subscribe(to: VideoPlayerEvents.ImmersiveViewingModeDidTransition.self, on: entity) { _ in
                Task { @MainActor in onChange() }
            },
            content.subscribe(to: VideoPlayerEvents.SpatialVideoModeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange() }
            },
            content.subscribe(to: VideoPlayerEvents.RenderingStatusDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange() }
            }
        ]
    }

    func cancel() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
    }
}

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    @State private var world = WorldSceneState()
    @State private var videoEntity = Entity()
    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var presentationObservation = SpatialPresentationObservation()
    private let logger = Logger(subsystem: "app.enchron", category: "SpatialSurface")

    public init() {}

    private var requestedPresentation: PlaybackPresentation {
        appModel.presentationTransition?.targetPresentation ?? appModel.playbackPresentation
    }

    public var body: some View {
        RealityView { content in
            if needsWorld {
                await loadWorld(into: content)
            }
            update(content)
        } update: { content in
            update(content)
        }
        .realityScripting()
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appModel.showControls.toggle()
                    }
                    if appModel.showControls { appModel.registerControlsInteraction() }
                }
        )
        .onDisappear {
            releaseSpatialSurface()
        }
    }

    private var needsWorld: Bool {
        requestedPresentation == .docked
            || (requestedPresentation == .window
                && appModel.environmentContext.environment != nil)
    }

    @MainActor
    private func update(_ content: RealityViewContent) {
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
            world.hasFailed = false
            return
        }

        if let entity = world.entity {
            if content.entities.contains(where: { $0 === entity }) == false {
                content.add(entity)
            }
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
        let entity = videoEntity
        entity.name = "EnchronVideo.\(presentation)"
        PlaybackRealityPresenter.configure(
            entity,
            renderer: renderer,
            presentation: presentation,
            stereoLayout: playbackRuntime.effectiveStereoLayout
        )
        subtitleSurface.update(
            on: entity,
            presentation: presentation,
            screenSize: entity.components[VideoPlayerComponent.self]?.playerScreenSize ?? .zero,
            reservedBottomFraction: 0,
            frame: playbackRuntime.activeSubtitleFrame
        )
        surfaceActivation.observe(entity, in: content) {
            attachSpatialSurfaceIfReady()
        }
        presentationObservation.observe(entity, in: content) {
            recordSpatialPresentationState()
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
        attachSpatialSurfaceIfReady()
    }

    @MainActor
    private func attachSpatialSurfaceIfReady() {
        let presentation = requestedPresentation
        guard presentation != .window,
              videoEntity.isActive,
              let renderer = playbackRuntime.renderer,
              PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: presentation
              ) else { return }
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

    @MainActor
    private func recordSpatialPresentationState() {
        let presentation = requestedPresentation
        let realityViewID = realityViewID(for: presentation)
        let parentID = videoEntity.parent.map { String(describing: ObjectIdentifier($0)) }
        guard let component = videoEntity.components[VideoPlayerComponent.self] else {
            playbackRuntime.recordPresentationState(
                presentation: presentation,
                phase: "surfaceAttached",
                realityViewID: realityViewID,
                entityParentID: parentID
            )
            return
        }
        let immersiveModeIsSettled = presentation != .panorama
            || component.immersiveViewingMode == component.desiredImmersiveViewingMode
        let isSettled = component.currentRenderingStatus == .ready
            && immersiveModeIsSettled
            && component.viewingMode == component.desiredViewingMode
            && component.spatialVideoMode == component.desiredSpatialVideoMode
        #if targetEnvironment(simulator)
        let simulatorIsConfigured = presentation == .panorama
            && component.currentRenderingStatus == .ready
            && (component.immersiveViewingMode == nil
                || component.immersiveViewingMode == component.desiredImmersiveViewingMode)
            && (component.viewingMode == nil
                || component.viewingMode == component.desiredViewingMode)
            && (component.spatialVideoMode == nil
                || component.spatialVideoMode == component.desiredSpatialVideoMode)
        #else
        let simulatorIsConfigured = false
        #endif
        playbackRuntime.recordPresentationState(
            presentation: presentation,
            phase: isSettled
                ? "settled"
                : simulatorIsConfigured ? "simulatorConfigured" : "surfaceAttached",
            realityViewID: realityViewID,
            entityParentID: parentID,
            desiredImmersiveViewingMode: String(describing: component.desiredImmersiveViewingMode),
            actualImmersiveViewingMode: component.immersiveViewingMode.map { String(describing: $0) },
            desiredViewingMode: String(describing: component.desiredViewingMode),
            actualViewingMode: component.viewingMode.map { String(describing: $0) },
            desiredSpatialVideoMode: String(describing: component.desiredSpatialVideoMode),
            actualSpatialVideoMode: String(describing: component.spatialVideoMode)
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
            content.add(entity)
            world.entity = entity
            world.playbackSurfaceAnchor = anchor
            logger.notice("world load completed")
            update(content)
        } catch {
            world.hasFailed = true
            logger.error("world load failed error=\(error.localizedDescription, privacy: .public)")
            playbackRuntime.lastErrorMessage = "Failed to load the selected environment: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func removeVideo(from content: RealityViewContent, reason: String) {
        logger.notice("video surface removed reason=\(reason, privacy: .public)")
        content.remove(videoEntity)
        releaseSpatialSurface()
    }

    @MainActor
    private func releaseSpatialSurface() {
        let presentation = playbackRuntime.rendererConsumerPresentation
            ?? playbackRuntime.attachedPresentation
        subtitleSurface.remove()
        surfaceActivation.cancel()
        presentationObservation.cancel()
        videoEntity.removeFromParent()
        videoEntity.components.remove(VideoPlayerComponent.self)
        if let presentation, presentation != .window {
            playbackRuntime.releaseRendererConsumer(
                presentation: presentation,
                entityID: entityID(for: presentation)
            )
        }
        detachSpatialSurface()
    }

    private func entityID(for presentation: PlaybackPresentation) -> String {
        "EnchronVideo.\(presentation)#\(ObjectIdentifier(videoEntity))"
    }

    private func realityViewID(for presentation: PlaybackPresentation) -> String {
        "EnchronRealityView.\(presentation)#\(ObjectIdentifier(videoEntity))"
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
