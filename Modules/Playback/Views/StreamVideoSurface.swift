import AVFoundation
import RealityKit
import SwiftUI

public struct StreamVideoSurface: View {
    public let renderer: AVSampleBufferVideoRenderer
    public let accessibilityIdentifier: String

    @State private var videoEntity = Entity()

    public init(
        renderer: AVSampleBufferVideoRenderer,
        accessibilityIdentifier: String = "Stream-Session-video"
    ) {
        self.renderer = renderer
        self.accessibilityIdentifier = accessibilityIdentifier
        videoEntity.name = "EnchronRealityView.streamVideo"
        videoEntity.isEnabled = true
    }

    public var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                installEntity(into: content)
                updateLayout(content: content, proxy: geometry)
            } update: { content in
                installEntity(into: content)
                updateLayout(content: content, proxy: geometry)
            }
            .frame(depth: WindowPlaybackSurfaceGeometry.flatWindowDepth)
        }
        .frame(depth: WindowPlaybackSurfaceGeometry.flatWindowDepth)
        .onDisappear {
            PlaybackRealityPresenter.releaseVideoRenderer(from: videoEntity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func installEntity(into content: RealityViewContent) {
        guard content.entities.contains(where: { $0 === videoEntity }) == false else {
            return
        }
        content.add(videoEntity)
    }

    private func updateLayout(content: RealityViewContent, proxy: GeometryProxy3D) {
        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: .window,
            requestsSpatialVideoMode: false
        )
        guard let component = videoEntity.components[VideoPlayerComponent.self] else {
            return
        }
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
            return
        }
        PlaybackSurfacePlacement.window(
            videoEntity,
            sceneCenter: layout.sceneCenter
        )
        videoEntity.scale = .init(repeating: layout.scale)
    }
}
