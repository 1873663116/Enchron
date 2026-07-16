import RealityKit
import SwiftUI

struct PlaybackVideoSurface: View {
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    let presentation: PlaybackPresentation
    let isActive: Bool

    @State private var videoEntity = Entity()
    @State private var surfaceActivation = PlaybackSurfaceActivation()

    var body: some View {
        RealityView { content in
            update(content)
        } update: { content in
            update(content)
        }
        .onDisappear {
            surfaceActivation.cancel()
            detachSurface()
        }
    }

    @MainActor
    private func update(_ content: RealityViewContent) {
        guard isActive, let renderer = playbackRuntime.renderer else {
            content.remove(videoEntity)
            detachSurface()
            return
        }

        videoEntity.name = "EnchronVideo.\(presentation)"
        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: presentation,
            stereoLayout: playbackRuntime.effectiveStereoLayout
        )
        surfaceActivation.observe(videoEntity, in: content) {
            attachSurfaceIfReady()
        }
        if content.entities.contains(where: { $0 === videoEntity }) == false {
            content.add(videoEntity)
        }
        attachSurfaceIfReady()
    }

    @MainActor
    private func attachSurfaceIfReady() {
        guard videoEntity.isActive,
              let renderer = playbackRuntime.renderer,
              isActive,
              PlaybackRealityPresenter.isBound(
                videoEntity,
                to: renderer,
                presentation: presentation
              ) else { return }
        do {
            try playbackRuntime.attach(
                entityID: entityID,
                realityViewID: realityViewID,
                presentation: presentation
            )
            playbackRuntime.recordPresentationState(
                presentation: presentation,
                phase: "surfaceAttached",
                realityViewID: realityViewID,
                entityParentID: videoEntity.parent.map { String(describing: ObjectIdentifier($0)) }
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    private var entityID: String {
        "EnchronVideo.\(presentation)#\(ObjectIdentifier(videoEntity))"
    }

    private var realityViewID: String {
        "EnchronRealityView.\(presentation)#\(ObjectIdentifier(videoEntity))"
    }

    private func detachSurface() {
        playbackRuntime.detachSurface(entityID: entityID, realityViewID: realityViewID)
    }
}
