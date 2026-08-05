import AVFoundation
import Foundation
import Observation
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import RealityKit
import SwiftUI

@MainActor
@Observable
final class PlaybackVideoEntityStore {
    private(set) var entity = Entity()
    @ObservationIgnored private var renderer: AVSampleBufferVideoRenderer?
    @ObservationIgnored private var videoComponentRevision: UInt64 = 0

    func entity(
        for renderer: AVSampleBufferVideoRenderer,
        videoComponentRevision: UInt64? = nil
    ) -> Entity {
        guard let currentRenderer = self.renderer else {
            self.renderer = renderer
            self.videoComponentRevision = videoComponentRevision ?? 0
            return entity
        }
        guard currentRenderer !== renderer else {
            if let videoComponentRevision,
               self.videoComponentRevision != videoComponentRevision {
                entity.components.remove(VideoPlayerComponent.self)
                self.videoComponentRevision = videoComponentRevision
            }
            return entity
        }
        entity.removeFromParent()
        entity = Entity()
        self.renderer = renderer
        self.videoComponentRevision = videoComponentRevision ?? 0
        return entity
    }

    func hasApplied(
        videoComponentRevision: UInt64,
        to renderer: AVSampleBufferVideoRenderer
    ) -> Bool {
        self.renderer === renderer && self.videoComponentRevision == videoComponentRevision
    }
}

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
        var shouldRequestRetry = false
        if observedEntityID != nextEntityID {
            cancel()
            observedEntityID = nextEntityID
            shouldRequestRetry = true
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
            shouldRequestRetry = true
        }
        #endif
        if shouldRequestRetry {
            requestRetry()
        }
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

/// Routes system accessibility activation for the actual RealityKit video
/// entity. The accessibility action and a spatial tap deliberately share one
/// dispatcher so neither path can acquire a different control-toggle policy.
@MainActor
enum PlaybackSurfaceInputAction {
    enum Source {
        case windowSwiftUI
        case spatialTap
        case accessibilityActivate
    }

    static func perform(
        _ source: Source,
        appModel: AppModel,
        at date: Date = Date()
    ) {
        _ = source
        appModel.toggleControlsFromPlaybackSurface(at: date)
    }
}

@MainActor
enum PlaybackSurfaceInputOwner: Equatable {
    case windowSwiftUIRoot
    case spatialVideoEntity
}

@MainActor
enum PlaybackSurfaceInputOwnership {
    static func owner(
        for presentation: PlaybackPresentation
    ) -> PlaybackSurfaceInputOwner {
        switch presentation {
        case .window:
            .windowSwiftUIRoot
        case .docked, .panorama:
            .spatialVideoEntity
        }
    }

    static func installsWindowRootTapSurface(
        for presentation: PlaybackPresentation
    ) -> Bool {
        owner(for: presentation) == .windowSwiftUIRoot
    }

    static func installsEntitySpatialTapGesture(
        for presentation: PlaybackPresentation
    ) -> Bool {
        owner(for: presentation) == .spatialVideoEntity
    }
}

@MainActor
final class PlaybackSurfaceAccessibilityActivationObservation {
    private var subscription: EventSubscription?
    private var observedEntityID: ObjectIdentifier?
    private var onActivate: (@MainActor () -> Void)?

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        in content: Content,
        onActivate: @escaping @MainActor () -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard observedEntityID != nextEntityID else {
            self.onActivate = onActivate
            return
        }
        cancel()
        observedEntityID = nextEntityID
        self.onActivate = onActivate
        #if os(visionOS)
        subscription = content.subscribe(
            to: AccessibilityEvents.Activate.self,
            on: entity
        ) { [weak self] event in
            guard event.entity === entity else { return }
            Task { @MainActor [weak self] in
                self?.onActivate?()
            }
        }
        #endif
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
        observedEntityID = nil
        onActivate = nil
    }
}

@MainActor
final class PlaybackRealityViewUpdateScheduler {
    private var pendingTask: Task<Void, Never>?

    func schedule(_ operation: @escaping @MainActor () async -> Void) {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard Task.isCancelled == false else { return }
            await operation()
            self?.pendingTask = nil
        }
    }

    func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}

@MainActor
final class PlaybackVideoRendererTargetObservation {
    private var entityID: ObjectIdentifier?
    private var videoComponentRevision: UInt64?
    private var subscriptions: [EventSubscription] = []
    private(set) var targetIsAvailable = false

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        videoComponentRevision: UInt64,
        in content: Content,
        onTargetAvailable: @escaping @MainActor () -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard entityID != nextEntityID
                || self.videoComponentRevision != videoComponentRevision else {
            return
        }
        cancel()
        entityID = nextEntityID
        self.videoComponentRevision = videoComponentRevision

        #if os(visionOS)
        let confirm: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.entityID == nextEntityID,
                      self.videoComponentRevision == videoComponentRevision,
                      self.targetIsAvailable == false else {
                    return
                }
                self.targetIsAvailable = true
                self.subscriptions.forEach { $0.cancel() }
                self.subscriptions.removeAll()
                onTargetAvailable()
            }
        }
        subscriptions = [
            content.subscribe(
                to: ComponentEvents.DidAdd.self,
                on: entity,
                componentType: VideoPlayerComponent.self
            ) { _ in
                confirm()
            },
            content.subscribe(
                to: ComponentEvents.DidChange.self,
                on: entity,
                componentType: VideoPlayerComponent.self
            ) { _ in
                confirm()
            }
        ]
        #else
        targetIsAvailable = true
        onTargetAvailable()
        #endif
    }

    func cancel() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
        videoComponentRevision = nil
        targetIsAvailable = false
    }
}

@MainActor
enum PlaybackModeRecoveryAction {
    case none
    case requestModesAgain
    case replaceRendererGraph
}

@MainActor
final class PlaybackModeRequestRetry {
    static let retryWindow: TimeInterval = 3
    static let minimumRequestInterval: TimeInterval = 0.25
    static let componentReplacementDelay: TimeInterval = 0.5

    private var requestSignature: String?
    private var firstRequestAt: Date?
    private var lastRequestAt: Date?
    private var componentReplacementSignature: String?

    func recoveryAction(
        entity _: Entity,
        presentation: PlaybackPresentation,
        desiredViewingMode: String,
        actualViewingMode: String?,
        desiredImmersiveViewingMode: String,
        actualImmersiveViewingMode: String?,
        requiresImmersiveViewingModeSettlement: Bool = false,
        now: Date = Date()
    ) -> PlaybackModeRecoveryAction {
        // A Window component can legitimately report no immersive mode before
        // its first displayed frame. Rewriting the component during that phase
        // can delay the frame that would make the mode observable. Panorama
        // requires progressive mode immediately; Window only retries when a
        // previous non-portal mode is still present.
        let immersiveModeNeedsAnotherRequest = actualImmersiveViewingMode
            != desiredImmersiveViewingMode
            && (presentation == .panorama
                || actualImmersiveViewingMode != nil
                || requiresImmersiveViewingModeSettlement)
        let normalizedDesiredViewingMode = desiredViewingMode
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let normalizedActualViewingMode = actualViewingMode?
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let viewingModeNeedsAnotherRequest = normalizedActualViewingMode
            != normalizedDesiredViewingMode
            && !(normalizedDesiredViewingMode == "mono"
                && normalizedActualViewingMode == nil
                && presentation != .panorama)
        guard viewingModeNeedsAnotherRequest
                || immersiveModeNeedsAnotherRequest else {
            reset()
            return .none
        }

        let nextSignature = [
            presentation.rawValue,
            desiredViewingMode,
            desiredImmersiveViewingMode
        ].joined(separator: "|")
        if requestSignature != nextSignature {
            requestSignature = nextSignature
            firstRequestAt = now
            lastRequestAt = nil
            componentReplacementSignature = nil
        }

        guard let firstRequestAt,
              now.timeIntervalSince(firstRequestAt) <= Self.retryWindow else {
            return .none
        }
        if (actualImmersiveViewingMode != nil
                || requiresImmersiveViewingModeSettlement),
           now.timeIntervalSince(firstRequestAt) >= Self.componentReplacementDelay,
           componentReplacementSignature != nextSignature {
            componentReplacementSignature = nextSignature
            lastRequestAt = now
            return .replaceRendererGraph
        }
        if let lastRequestAt,
           now.timeIntervalSince(lastRequestAt) < Self.minimumRequestInterval {
            return .none
        }
        self.lastRequestAt = now
        return .requestModesAgain
    }

    func reset() {
        requestSignature = nil
        firstRequestAt = nil
        lastRequestAt = nil
        componentReplacementSignature = nil
    }
}

@MainActor
enum PanoramaTargetBootstrapPhase { case portal, progressive }

@MainActor
enum PlaybackRealityPresenter {
    static let playbackSurfaceAccessibilityLabel: LocalizedStringResource =
        "Playback surface"

    static func configure(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation,
        stereoLayout: PlaybackModel.StereoLayout,
        panoramaTargetBootstrapPhase: PanoramaTargetBootstrapPhase = .progressive,
        requestsProgressiveImmersiveViewingMode: Bool = false
    ) {
        entity.components.remove(ModelComponent.self)
        configureVideoPlayer(
            entity,
            renderer: renderer,
            stereoLayout: stereoLayout,
            presentation: presentation,
            panoramaTargetBootstrapPhase: panoramaTargetBootstrapPhase,
            requestsProgressiveImmersiveViewingMode:
                requestsProgressiveImmersiveViewingMode
        )
        #if os(visionOS)
        if presentation == .window {
            entity.components.set(
                ModelSortGroupComponent(
                    group: .planarUIInline,
                    order: WindowPlaybackSurfaceGeometry.backgroundSortOrder
                )
            )
        } else {
            entity.components.remove(ModelSortGroupComponent.self)
        }
        #endif
        // Window surface taps belong to the SwiftUI root overlay so chrome and
        // secondary menus can receive gaze + pinch without competing with a
        // RealityKit hit target. Docked and Panorama have no such overlay on
        // the video, so the entity owns spatial input there. Presentation
        // transitions disable the enclosing RealityView instead of stripping
        // these components from a settled spatial surface.
        switch presentation {
        case .window:
            entity.components.remove(InputTargetComponent.self)
            entity.components.remove(CollisionComponent.self)
        case .docked, .panorama:
            #if os(visionOS)
            let collisionShape: ShapeResource =
                presentation == .panorama
                ? .generateSphere(radius: 1)
                : .generateBox(size: [1.8, 1, 0.01])
            #else
            let collisionShape = ShapeResource.generateBox(size: [1.8, 1, 0.01])
            #endif
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [collisionShape]))
        }
        #if os(visionOS)
        var accessibility = AccessibilityComponent()
        accessibility.isAccessibilityElement = true
        accessibility.label = playbackSurfaceAccessibilityLabel
        accessibility.systemActions = [.activate]
        entity.components.set(accessibility)
        #endif
    }

    static func isBound(
        _ entity: Entity,
        to renderer: AVSampleBufferVideoRenderer,
        presentation: PlaybackPresentation
    ) -> Bool {
        entity.components[VideoPlayerComponent.self]?.videoRenderer === renderer
    }

    static func releaseVideoRenderer(from entity: Entity) {
        entity.components.remove(VideoPlayerComponent.self)
    }

    static func setOpacity(
        of entity: Entity,
        to opacity: Float,
        animated: Bool
    ) {
        guard let current = entity.components[OpacityComponent.self] else {
            entity.components.set(OpacityComponent(opacity: opacity))
            return
        }
        guard current.opacity != opacity else { return }
        guard animated else {
            entity.components.set(OpacityComponent(opacity: opacity))
            return
        }
        Entity.animate(
            PlaybackPresentationTransitionAppearance.animation(
                for: Double(opacity)
            )
        ) {
            entity.components[OpacityComponent.self]?.opacity = opacity
        }
    }

    static func reapplyDesiredModesAfterSceneActivation(
        _ entity: Entity,
        presentation: PlaybackPresentation,
        panoramaTargetBootstrapPhase: PanoramaTargetBootstrapPhase = .progressive,
        stereoLayout: PlaybackModel.StereoLayout,
        requestsProgressiveImmersiveViewingMode: Bool = false
    ) {
        guard var component = entity.components[VideoPlayerComponent.self] else { return }
        #if os(visionOS)
        component.desiredViewingMode = stereoLayout == .mono ? .mono : .stereo
        component.desiredImmersiveViewingMode = immersiveViewingMode(
            for: presentation,
            panoramaTargetBootstrapPhase: panoramaTargetBootstrapPhase,
            requestsProgressiveImmersiveViewingMode:
                requestsProgressiveImmersiveViewingMode
        )
        #else
        component.desiredViewingMode = .mono
        #endif
        entity.components.set(component)
    }

    private static func configureVideoPlayer(
        _ entity: Entity,
        renderer: AVSampleBufferVideoRenderer,
        stereoLayout: PlaybackModel.StereoLayout,
        presentation: PlaybackPresentation,
        panoramaTargetBootstrapPhase: PanoramaTargetBootstrapPhase,
        requestsProgressiveImmersiveViewingMode: Bool
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
            let requestedImmersiveViewingMode = immersiveViewingMode(
                for: presentation,
                panoramaTargetBootstrapPhase: panoramaTargetBootstrapPhase,
                requestsProgressiveImmersiveViewingMode:
                    requestsProgressiveImmersiveViewingMode
            )
            needsUpdate = needsUpdate
                || component.desiredImmersiveViewingMode != requestedImmersiveViewingMode
            component.desiredImmersiveViewingMode = requestedImmersiveViewingMode
            #endif
            if needsUpdate {
                entity.components.set(component)
            }
            return
        }
        var component = VideoPlayerComponent(videoRenderer: renderer)
        component.desiredViewingMode = viewingMode
        #if os(visionOS)
        component.desiredImmersiveViewingMode = immersiveViewingMode(
            for: presentation,
            panoramaTargetBootstrapPhase: panoramaTargetBootstrapPhase,
            requestsProgressiveImmersiveViewingMode:
                requestsProgressiveImmersiveViewingMode
        )
        #endif
        entity.components.set(component)
    }

    #if os(visionOS)
    private static func immersiveViewingMode(
        for presentation: PlaybackPresentation,
        panoramaTargetBootstrapPhase: PanoramaTargetBootstrapPhase,
        requestsProgressiveImmersiveViewingMode: Bool
    ) -> VideoPlayerComponent.ImmersiveViewingMode {
        (presentation == .panorama && panoramaTargetBootstrapPhase == .progressive)
            || requestsProgressiveImmersiveViewingMode
            ? .progressive
            : .portal
    }
    #endif
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
