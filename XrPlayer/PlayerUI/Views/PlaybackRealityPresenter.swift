import AVFoundation
import PlaybackCore
import RealityKit
import SwiftUI

@MainActor
final class PlaybackSurfaceActivation {
    private var subscription: EventSubscription?
    private var activationTask: Task<Void, Never>?

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        in content: Content,
        onActivate: @escaping @MainActor () -> Void
    ) {
        guard subscription == nil, activationTask == nil else { return }
        #if os(macOS)
        activationTask = Task { @MainActor in
            for _ in 0..<200 {
                guard Task.isCancelled == false else { return }
                if entity.isActive {
                    onActivate()
                    activationTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            activationTask = nil
        }
        #else
        subscription = content.subscribe(
            to: SceneEvents.DidActivateEntity.self,
            on: entity
        ) { event in
            guard event.entity === entity else { return }
            Task { @MainActor in onActivate() }
        }
        #endif
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
        activationTask?.cancel()
        activationTask = nil
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
        entity.components.remove(ModelComponent.self)
        configureVideoPlayer(
            entity,
            renderer: renderer,
            presentation: presentation,
            stereoLayout: stereoLayout
        )
        entity.components.set(InputTargetComponent())
        #if os(visionOS)
        let collisionShape: ShapeResource = presentation == .panorama
            ? .generateSphere(radius: 1)
            : .generateBox(size: [1.8, 1, 0.01])
        #else
        let collisionShape = ShapeResource.generateBox(size: [1.8, 1, 0.01])
        #endif
        entity.components.set(CollisionComponent(shapes: [collisionShape]))
    }

    static func isBound(
        _ entity: Entity,
        to renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation
    ) -> Bool {
        entity.components[VideoPlayerComponent.self]?.videoRenderer === renderer
    }

    private static func configureVideoPlayer(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation,
        stereoLayout: PlaybackModel.StereoLayout
    ) {
        #if os(visionOS)
        let viewingMode: VideoPlaybackController.ViewingMode = stereoLayout == .mono ? .mono : .stereo
        #else
        let viewingMode: VideoPlaybackController.ViewingMode = .mono
        #endif
        if var component = entity.components[VideoPlayerComponent.self],
           component.videoRenderer === renderer {
            var needsUpdate = component.desiredViewingMode != viewingMode
            component.desiredViewingMode = viewingMode
            #if os(visionOS)
            let immersiveViewingMode: VideoPlayerComponent.ImmersiveViewingMode =
                presentation == .panorama ? .progressive : .portal
            needsUpdate = needsUpdate
                || component.desiredImmersiveViewingMode != immersiveViewingMode
            component.desiredImmersiveViewingMode = immersiveViewingMode
            #endif
            if needsUpdate {
                entity.components.set(component)
            }
            return
        }
        var component = VideoPlayerComponent(videoRenderer: renderer)
        component.desiredViewingMode = viewingMode
        #if os(visionOS)
        component.desiredImmersiveViewingMode = presentation == .panorama ? .progressive : .portal
        #endif
        entity.components.set(component)
    }
}

@MainActor
enum PlaybackSubtitlePresenter {
    private static let canvasSize = CGSize(width: 1_600, height: 220)
    private static let pointsToMeters: Float = 0.0254 / 72

    static func update(
        _ subtitleEntity: Entity,
        on videoEntity: Entity,
        presentation: PlaybackPresentation,
        screenSize: SIMD2<Float>,
        cues: [PlaybackSubtitleCue]
    ) {
        let text = cues
            .map(\.text)
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        guard presentation != .panorama,
              text.isEmpty == false else {
            subtitleEntity.isEnabled = false
            return
        }

        var attributedText = AttributedString(text)
        attributedText.font = .system(size: 56, weight: .semibold)
        attributedText.foregroundColor = .white

        var component = TextComponent()
        component.size = canvasSize
        component.text = attributedText
        component.backgroundColor = CGColor(gray: 0, alpha: 0.62)
        component.cornerRadius = 24

        subtitleEntity.name = "Enchron.ActiveSubtitles"
        subtitleEntity.components.set(component)
        if subtitleEntity.parent !== videoEntity {
            videoEntity.addChild(subtitleEntity)
        }

        let resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : SIMD2<Float>(16.0 / 9.0, 1)
        let canvasWidth = Float(canvasSize.width) * pointsToMeters
        let scale = resolvedScreenSize.x * 0.82 / canvasWidth
        subtitleEntity.scale = .init(repeating: scale)
        subtitleEntity.position = [0, -resolvedScreenSize.y * 0.35, 0.015]
        subtitleEntity.isEnabled = true
    }

    static func remove(_ subtitleEntity: Entity) {
        subtitleEntity.removeFromParent()
        subtitleEntity.components.remove(TextComponent.self)
        subtitleEntity.isEnabled = false
    }
}
