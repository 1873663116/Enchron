import AVFoundation
import OSLog
import RealityKit
import RealityKitScripting
import SwiftUI

@MainActor
private final class WorldSceneState {
    var entity: Entity?
    var isLoading = false
    var hasFailed = false
}

public struct ImmersiveSpaceView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    @State private var world = WorldSceneState()
    @State private var videoEntity = Entity()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
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
            surfaceActivation.cancel()
            detachSpatialSurface()
        }
    }

    private var needsWorld: Bool {
        requestedPresentation == .docked || appModel.isEnvironmentImmersiveActive
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
        guard presentation != .docked || world.entity != nil else { return }

        presentVideo(in: content, with: renderer, as: presentation)
    }

    @MainActor
    private func updateWorld(in content: RealityViewContent) {
        guard needsWorld else {
            if let entity = world.entity { content.remove(entity) }
            world.entity = nil
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
            stereoLayout: appModel.effectiveStereoLayout
        )
        surfaceActivation.observe(entity, in: content) {
            attachSpatialSurfaceIfReady()
        }
        if presentation == .docked {
            positionDockedVideo(entity)
        } else {
            entity.position = .zero
            entity.orientation = .init()
            entity.scale = .one
        }
        if content.entities.contains(where: { $0 === entity }) == false {
            content.add(entity)
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
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadWorld(into content: RealityViewContent) async {
        guard world.entity == nil, world.isLoading == false, world.hasFailed == false else { return }
        world.isLoading = true
        defer { world.isLoading = false }
        logger.notice("world load started")
        do {
            let entity = try await Entity(named: "world")
            content.add(entity)
            world.entity = entity
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

    private func positionDockedVideo(_ entity: Entity) {
        entity.position = [
            0,
            Float(appModel.screenVerticalOffset),
            -Float(appModel.screenDistance)
        ]
        entity.orientation = simd_quatf(
            angle: Float(appModel.screenViewAngle * .pi / 180),
            axis: [1, 0, 0]
        )
    }
}
