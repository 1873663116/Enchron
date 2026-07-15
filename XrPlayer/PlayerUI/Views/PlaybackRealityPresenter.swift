import AVFoundation
import RealityKit
import SwiftUI

@MainActor
final class PlaybackSurfaceActivation {
    private var subscription: EventSubscription?

    func observe(
        _ entity: Entity,
        in content: RealityViewContent,
        onActivate: @escaping @MainActor () -> Void
    ) {
        guard subscription == nil else { return }
        subscription = content.subscribe(
            to: SceneEvents.DidActivateEntity.self,
            on: entity
        ) { event in
            guard event.entity === entity else { return }
            Task { @MainActor in onActivate() }
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
    }
}

@MainActor
enum PlaybackRealityPresenter {
    static func configure(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        if presentation == .panorama {
            configurePanorama(entity, renderer: renderer, stereoLayout: stereoLayout)
        } else {
            configurePlanar(entity, renderer: renderer, stereoLayout: stereoLayout)
        }
        entity.components.set(InputTargetComponent())
    }

    static func isBound(
        _ entity: Entity,
        to renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation
    ) -> Bool {
        if presentation == .panorama {
            return entity.components[VideoPlayerComponent.self]?.videoRenderer === renderer
        }
        guard let model = entity.components[ModelComponent.self] else { return false }
        return model.materials.lazy.compactMap { $0 as? VideoMaterial }.first?.videoRenderer === renderer
    }

    private static func configurePlanar(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        entity.components.remove(VideoPlayerComponent.self)
        if let model = entity.components[ModelComponent.self],
           let material = model.materials.first as? VideoMaterial,
           material.videoRenderer === renderer {
            material.controller.preferredViewingMode = stereoLayout == .mono ? .mono : .stereo
            return
        }
        let material = VideoMaterial(videoRenderer: renderer)
        material.controller.preferredViewingMode = stereoLayout == .mono ? .mono : .stereo
        let mesh = MeshResource.generatePlane(width: 1.6, height: 0.9)
        entity.components.set(ModelComponent(mesh: mesh, materials: [material]))
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: [1.6, 0.9, 0.01])]))
    }

    private static func configurePanorama(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        entity.components.remove(ModelComponent.self)
        let viewingMode: VideoPlaybackController.ViewingMode = stereoLayout == .mono ? .mono : .stereo
        if var component = entity.components[VideoPlayerComponent.self],
           component.videoRenderer === renderer {
            if component.desiredViewingMode != viewingMode
                || component.desiredImmersiveViewingMode != .progressive {
                component.desiredViewingMode = viewingMode
                component.desiredImmersiveViewingMode = .progressive
                entity.components.set(component)
            }
            return
        }
        var component = VideoPlayerComponent(videoRenderer: renderer)
        component.desiredViewingMode = viewingMode
        component.desiredImmersiveViewingMode = .progressive
        entity.components.set(component)
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 1)]))
    }
}
