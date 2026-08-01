import AVFoundation
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import RealityKit
import SwiftUI

@MainActor
final class PlaybackSurfaceActivation {
    private var subscription: EventSubscription?
    private var retryTask: Task<Void, Never>?
    private var observedEntityID: ObjectIdentifier?
    private var onActivate: (@MainActor () -> Void)?

    static let maximumRetryCountForView = 120
    static let retryIntervalForView = Duration.milliseconds(25)

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        in content: Content,
        onActivate: @escaping @MainActor () -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        if observedEntityID != nextEntityID {
            cancel()
            observedEntityID = nextEntityID
        }
        self.onActivate = onActivate
        #if os(visionOS)
        if subscription == nil {
            subscription = content.subscribe(
                to: SceneEvents.DidActivateEntity.self,
                on: entity
            ) { [weak self] event in
                guard event.entity === entity else { return }
                Task { @MainActor [weak self] in
                    self?.onActivate?()
                    self?.requestRetry()
                }
            }
        }
        #endif
        requestRetry()
    }

    /// RealityKit can publish activation before the renderer or format
    /// projection is ready (and vice versa). Re-run the idempotent attach
    /// check for a bounded window so either ordering can converge.
    func requestRetry() {
        guard retryTask == nil, onActivate != nil else { return }
        retryTask = Task { @MainActor [weak self] in
            for _ in 0..<Self.maximumRetryCountForView {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.onActivate?()
                try? await Task.sleep(for: Self.retryIntervalForView)
            }
            self?.retryTask = nil
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
        retryTask?.cancel()
        retryTask = nil
        observedEntityID = nil
        onActivate = nil
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
        if presentation == .window {
            entity.components.set(
                ModelSortGroupComponent(
                    group: .planarUIAlwaysBehind,
                    order: WindowPlaybackSurfaceGeometry.backgroundSortOrder
                )
            )
        } else {
            entity.components.remove(ModelSortGroupComponent.self)
        }
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

struct PlaybackSubtitleLayout: Equatable {
    let size: SIMD2<Float>
    let position: SIMD3<Float>
}

enum PlaybackSubtitlePlacement {
    static func resolve(
        frame: PlaybackSubtitleFrame,
        screenSize: SIMD2<Float>,
        reservedBottomFraction: Float
    ) -> PlaybackSubtitleLayout {
        let resolvedScreenSize = screenSize.x > 0 && screenSize.y > 0
            ? screenSize
            : SIMD2<Float>(16.0 / 9.0, 1)
        let canvasWidth = Float(frame.canvasWidth)
        let canvasHeight = Float(frame.canvasHeight)
        let contentWidth = resolvedScreenSize.x * Float(frame.contentWidth) / canvasWidth
        let contentHeight = resolvedScreenSize.y * Float(frame.contentHeight) / canvasHeight
        let centerX = -resolvedScreenSize.x / 2 +
            resolvedScreenSize.x * (Float(frame.contentX) + Float(frame.contentWidth) / 2) / canvasWidth
        let centerY = resolvedScreenSize.y / 2 -
            resolvedScreenSize.y * (Float(frame.contentY) + Float(frame.contentHeight) / 2) / canvasHeight
        let contentBottomY = centerY - contentHeight / 2
        let safeBottomY = -resolvedScreenSize.y / 2 +
            resolvedScreenSize.y * min(max(reservedBottomFraction, 0), 0.5)
        let safeCenterY = centerY + max(0, safeBottomY - contentBottomY)
        return PlaybackSubtitleLayout(
            size: [contentWidth, contentHeight],
            position: [centerX, safeCenterY, 0.015]
        )
    }
}

@MainActor
final class PlaybackSubtitleSurface {
    let entity = Entity()

    private var texture: TextureResource?
    private var textureSize = SIMD2<Int>(repeating: 0)
    private var changeIdentifier: UInt64?
    private var layout: PlaybackSubtitleLayout?

    func update(
        on videoEntity: Entity,
        presentation: PlaybackPresentation,
        screenSize: SIMD2<Float>,
        reservedBottomFraction: Float,
        frame: PlaybackSubtitleFrame?
    ) {
        guard presentation != .panorama,
              let frame,
              frame.contentWidth > 0,
              frame.contentHeight > 0,
              frame.canvasWidth > 0,
              frame.canvasHeight > 0 else {
            if frame == nil || presentation == .panorama {
                entity.isEnabled = false
                changeIdentifier = nil
                layout = nil
            }
            return
        }
        let nextLayout = PlaybackSubtitlePlacement.resolve(
            frame: frame,
            screenSize: screenSize,
            reservedBottomFraction: reservedBottomFraction
        )
        let frameChanged = changeIdentifier != frame.changeIdentifier
        guard frameChanged || layout != nextLayout else { return }
        if frameChanged {
            guard let image = Self.image(frame) else {
                entity.isEnabled = false
                return
            }
            let nextSize = SIMD2(frame.contentWidth, frame.contentHeight)
            do {
                if let texture, textureSize == nextSize {
                    try texture.replace(
                        withImage: image,
                        options: .init(semantic: .color)
                    )
                } else {
                    texture = try TextureResource(
                        image: image,
                        options: .init(semantic: .color)
                    )
                    textureSize = nextSize
                }
            } catch {
                entity.isEnabled = false
                return
            }
        }

        guard let texture else { return }
        var material = UnlitMaterial(texture: texture)
        material.blending = .transparent(opacity: .init(scale: 1))
        entity.name = "Enchron.ActiveSubtitleFrame.\(frame.kind.rawValue)"
        entity.components.set(ModelComponent(
            mesh: .generatePlane(width: nextLayout.size.x, height: nextLayout.size.y),
            materials: [material]
        ))
        if entity.parent !== videoEntity {
            videoEntity.addChild(entity)
        }
        entity.position = nextLayout.position
        entity.isEnabled = true
        changeIdentifier = frame.changeIdentifier
        layout = nextLayout
    }

    func remove() {
        entity.removeFromParent()
        entity.components.remove(ModelComponent.self)
        entity.isEnabled = false
        texture = nil
        textureSize = .zero
        changeIdentifier = nil
        layout = nil
    }

    private static func image(_ frame: PlaybackSubtitleFrame) -> CGImage? {
        guard frame.premultipliedBGRA.count == frame.bytesPerRow * frame.contentHeight,
              let provider = CGDataProvider(data: frame.premultipliedBGRA as CFData) else {
            return nil
        }
        return CGImage(
            width: frame.contentWidth,
            height: frame.contentHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedFirst.rawValue |
                CGBitmapInfo.byteOrder32Little.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
