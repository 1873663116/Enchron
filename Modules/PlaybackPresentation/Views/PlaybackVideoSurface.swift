import RealityKit
import OSLog
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

private let playbackVideoSurfaceLogger = Logger(
    subsystem: "com.xiongzhipeng.XTransferPlayer",
    category: "PlaybackVideoSurface"
)

@MainActor
private final class PlaybackVideoComponentObservation {
    private var entityID: ObjectIdentifier?
    private var subscriptions: [EventSubscription] = []
    private var lastLayoutSignature: String?

    func observe<Content: RealityViewContentProtocol>(
        _ entity: Entity,
        in content: Content,
        onChange: @escaping @MainActor (String) -> Void
    ) {
        let nextEntityID = ObjectIdentifier(entity)
        guard entityID != nextEntityID else { return }
        cancel()
        entityID = nextEntityID
        #if os(visionOS)
        subscriptions = [
            content.subscribe(to: VideoPlayerEvents.VideoSizeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange("videoSizeDidChange") }
            },
            content.subscribe(to: VideoPlayerEvents.ViewingModeDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange("viewingModeDidChange") }
            },
            content.subscribe(to: VideoPlayerEvents.RenderingStatusDidChange.self, on: entity) { _ in
                Task { @MainActor in onChange("renderingStatusDidChange") }
            }
        ]
        #endif
    }

    func cancel() {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        entityID = nil
    }

    func shouldLogLayout(_ signature: String) -> Bool {
        guard lastLayoutSignature != signature else { return false }
        lastLayoutSignature = signature
        return true
    }
}

struct PlaybackVideoSurface: View {
    private static let subtitleControlSafeAreaFraction: Float = 0.32

    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    let presentation: PlaybackPresentation
    let isActive: Bool

    @State private var videoEntity = Entity()
    @State private var subtitleSurface = PlaybackSubtitleSurface()
    @State private var surfaceActivation = PlaybackSurfaceActivation()
    @State private var componentObservation = PlaybackVideoComponentObservation()
    @State private var componentRevision = 0
    #if os(macOS)
    @State private var macOSWindowCamera = Entity()
    @State private var macOSWorld: Entity?
    @State private var macOSPlaybackSurfaceAnchor: Entity?
    @State private var isLoadingMacOSWorld = false
    @State private var macOSWorldLoadError: String?
    #endif

    @ViewBuilder
    var body: some View {
        ZStack {
            #if os(visionOS)
            visionSurface
            #else
            macOSSurface
            #endif

            if let activeSubtitleText {
                Text(activeSubtitleText)
                    .frame(width: 1, height: 1)
                    .clipped()
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Subtitles")
                    .accessibilityValue(activeSubtitleText)
                    .accessibilityIdentifier("PlayerUI-active-subtitles")
            }
        }
    }

    #if os(visionOS)
    private var visionSurface: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                updateVisionSurface(
                    content,
                    proxy: geometry,
                    revision: componentRevision
                )
            } update: { content in
                updateVisionSurface(
                    content,
                    proxy: geometry,
                    revision: componentRevision
                )
            }
            .gesture(surfaceTapGesture)
            .frame(depth: WindowPlaybackSurfaceGeometry.flatDepth)
        }
        .frame(depth: WindowPlaybackSurfaceGeometry.flatDepth)
        .onDisappear {
            releaseSurface()
        }
    }
    #else
    private var macOSSurface: some View {
        GeometryReader { geometry in
            ZStack {
                RealityView { content in
                    updateMacOSSurface(
                        &content,
                        canvasSize: geometry.size,
                        revision: componentRevision
                    )
                } update: { content in
                    updateMacOSSurface(
                        &content,
                        canvasSize: geometry.size,
                        revision: componentRevision
                    )
                }
                .realityViewCameraControls(presentation == .docked ? .orbit : .none)
                .background(.black)
                .gesture(surfaceTapGesture)
                .allowsHitTesting(appModel.showControls == false)

                if presentation == .docked, isLoadingMacOSWorld {
                    ProgressView("Loading environment…")
                }

                if presentation == .docked, let macOSWorldLoadError {
                    ContentUnavailableView(
                        "Environment Unavailable",
                        systemImage: "cube.transparent",
                        description: Text(macOSWorldLoadError)
                    )
                }

                if appModel.showControls, isActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggleControlsFromSurface)
                }
            }
            .task(id: presentation) {
                guard presentation == .docked else { return }
                await loadMacOSWorldIfNeeded()
                componentRevision &+= 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MacPlayback-\(presentation.rawValue)-SceneHost")
        .accessibilityValue(playbackRuntime.lifecycle.label)
        .onDisappear {
            releaseSurface()
        }
    }
    #endif

    private var surfaceTapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToEntity(videoEntity)
            .onEnded { _ in toggleControlsFromSurface() }
    }

    private func toggleControlsFromSurface() {
        withAnimation(.easeInOut(duration: 0.25)) {
            appModel.toggleControlsFromPlaybackSurface()
        }
    }

    @MainActor
    private func prepareSurface<Content: RealityViewContentProtocol>(
        in content: Content,
        revision: Int
    ) -> Bool {
        _ = revision
        guard isActive,
              playbackRuntime.mediaFormatIsKnown,
              let renderer = playbackRuntime.renderer else {
            releaseSurface(from: content)
            return false
        }

        do {
            try playbackRuntime.claimRendererConsumer(
                presentation: presentation,
                entityID: entityID
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
            releaseSurface(from: content)
            return false
        }

        #if os(macOS)
        let needsInsertion = presentation == .window
            && content.entities.contains(where: { $0 === videoEntity }) == false
        #else
        let needsInsertion = content.entities.contains(where: { $0 === videoEntity }) == false
        #endif
        videoEntity.name = "EnchronVideo.\(presentation)"
        PlaybackRealityPresenter.configure(
            videoEntity,
            renderer: renderer,
            presentation: presentation,
            stereoLayout: playbackRuntime.effectiveStereoLayout
        )
        subtitleSurface.update(
            on: videoEntity,
            presentation: presentation,
            screenSize: component?.playerScreenSize ?? .zero,
            reservedBottomFraction: appModel.showControls
                ? Self.subtitleControlSafeAreaFraction
                : 0,
            frame: playbackRuntime.activeSubtitleFrame
        )
        componentObservation.observe(videoEntity, in: content) { reason in
            logComponentState(reason: reason)
            componentRevision &+= 1
        }
        surfaceActivation.observe(videoEntity, in: content) {
            attachSurfaceIfReady()
        }
        if needsInsertion {
            content.add(videoEntity)
            logComponentState(reason: "entityAdded")
        }
        attachSurfaceIfReady()
        return true
    }

    #if os(visionOS)
    @MainActor
    private func updateVisionSurface(
        _ content: RealityViewContent,
        proxy: GeometryProxy3D,
        revision: Int
    ) {
        guard prepareSurface(in: content, revision: revision) else { return }
        _ = scaleToFitWindow(videoEntity, proxy: proxy, content: content)
    }

    @MainActor
    private func scaleToFitWindow(
        _ entity: Entity,
        proxy: GeometryProxy3D,
        content: RealityViewContent
    ) -> SIMD3<Float>? {
        guard let component = entity.components[VideoPlayerComponent.self] else { return nil }
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
            return nil
        }
        PlaybackSurfacePlacement.window(
            entity,
            sceneCenter: layout.sceneCenter
        )
        entity.scale = .init(repeating: layout.scale)
        let layoutSignature =
            "\(layout.sceneCenter)-\(layout.availableSize)-\(resolvedScreenSize)-\(layout.scale)"
        if componentObservation.shouldLogLayout(layoutSignature) {
            playbackVideoSurfaceLogger.notice(
                "window layout sceneCenter=\(String(describing: layout.sceneCenter), privacy: .public) sceneSize=\(String(describing: layout.availableSize), privacy: .public) screenSize=\(String(describing: resolvedScreenSize), privacy: .public) renderedSize=\(String(describing: layout.renderedSize), privacy: .public) scale=\(layout.scale)"
            )
        }
        return [
            layout.availableSize.x,
            layout.availableSize.y,
            Float(sceneBounds.extents.z)
        ]
    }

    #else
    @MainActor
    private func updateMacOSSurface(
        _ content: inout RealityViewCameraContent,
        canvasSize: CGSize,
        revision: Int
    ) {
        content.camera = .virtual
        if let macOSWorld {
            if content.entities.contains(where: { $0 === macOSWorld }) == false {
                content.add(macOSWorld)
            }
            macOSWorld.isEnabled = presentation == .docked
        }
        guard presentation != .panorama else {
            playbackRuntime.lastErrorMessage = "Panorama presentation is available on visionOS."
            return
        }
        if presentation == .docked, macOSPlaybackSurfaceAnchor == nil {
            if let macOSWorldLoadError {
                playbackRuntime.lastErrorMessage = macOSWorldLoadError
            }
            return
        }
        guard prepareSurface(in: content, revision: revision) else {
            content.cameraTarget = nil
            return
        }
        switch presentation {
        case .window:
            if content.entities.contains(where: { $0 === videoEntity }) == false {
                content.add(videoEntity)
            }
            PlaybackSurfacePlacement.window(videoEntity)
            configureMacOSWindowCamera(in: &content, canvasSize: canvasSize)
        case .docked:
            content.remove(macOSWindowCamera)
            guard let macOSPlaybackSurfaceAnchor else { return }
            PlaybackSurfacePlacement.dock(
                videoEntity,
                to: macOSPlaybackSurfaceAnchor,
                transform: .init(
                    distance: appModel.screenDepthOffset,
                    elevationDegrees: appModel.screenViewAngle,
                    scale: appModel.screenScale
                )
            )
        case .panorama:
            return
        }
        content.cameraTarget = presentation == .docked ? videoEntity : nil
        attachSurfaceIfReady()
    }

    @MainActor
    private func configureMacOSWindowCamera(
        in content: inout RealityViewCameraContent,
        canvasSize: CGSize
    ) {
        let geometry = MacWindowPlaybackCameraGeometry.resolve(
            screenSize: macOSWindowScreenSize,
            canvasSize: canvasSize
        )
        if content.entities.contains(where: { $0 === macOSWindowCamera }) == false {
            content.add(macOSWindowCamera)
        }
        macOSWindowCamera.components.set(
            PerspectiveCameraComponent(
                near: 0.01,
                far: 100,
                fieldOfViewInDegrees: MacWindowPlaybackCameraGeometry.fieldOfViewInDegrees,
                fieldOfViewOrientation: .vertical
            )
        )
        macOSWindowCamera.look(
            at: .zero,
            from: [0, 0, geometry.distance],
            relativeTo: nil
        )
        let signature = "macOS-window-\(canvasSize)-\(geometry.screenSize)-\(geometry.distance)"
        if componentObservation.shouldLogLayout(signature) {
            playbackVideoSurfaceLogger.notice(
                "macOS window camera canvasSize=\(String(describing: canvasSize), privacy: .public) screenSize=\(String(describing: geometry.screenSize), privacy: .public) distance=\(geometry.distance)"
            )
        }
    }

    private var macOSWindowScreenSize: SIMD2<Float> {
        if let componentSize = component?.playerScreenSize,
           componentSize.x > 0,
           componentSize.y > 0 {
            return componentSize
        }
        guard let resolution = playbackRuntime.displayMediaProfile?.resolution,
              resolution.width > 0,
              resolution.height > 0 else { return .zero }
        let output = playbackRuntime.effectiveStereoLayout.outputDimensions(
            inputWidth: resolution.width,
            inputHeight: resolution.height
        )
        guard output.width > 0, output.height > 0 else { return .zero }
        return [Float(output.width) / Float(output.height), 1]
    }

    @MainActor
    private func loadMacOSWorldIfNeeded() async {
        guard macOSWorld == nil,
              isLoadingMacOSWorld == false,
              macOSWorldLoadError == nil else { return }
        isLoadingMacOSWorld = true
        defer { isLoadingMacOSWorld = false }
        do {
            let world = try await Entity(named: EnvironmentSceneMapping.worldSceneName)
            macOSPlaybackSurfaceAnchor = try PlaybackSurfaceAnchorResolver.resolve(in: world)
            world.isEnabled = false
            macOSWorld = world
            playbackVideoSurfaceLogger.notice("macOS RCP world loaded for shared playback RealityView")
        } catch {
            macOSWorldLoadError = error.localizedDescription
            playbackVideoSurfaceLogger.error(
                "macOS RCP world load failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }
    #endif

    @MainActor
    private func attachSurfaceIfReady() {
        let renderer = playbackRuntime.renderer
        let isBound = renderer.map {
            PlaybackRealityPresenter.isBound(
                videoEntity,
                to: $0,
                presentation: presentation
            )
        } ?? false
        guard videoEntity.isActive,
              renderer != nil,
              isActive,
              playbackRuntime.mediaFormatIsKnown,
              isBound else { return }
        do {
            try playbackRuntime.attach(
                entityID: entityID,
                realityViewID: realityViewID,
                presentation: presentation
            )
            playbackRuntime.recordPresentationState(
                presentation: presentation,
                phase: presentationPhase,
                realityViewID: realityViewID,
                entityParentID: videoEntity.parent.map { String(describing: ObjectIdentifier($0)) },
                desiredImmersiveViewingMode: desiredImmersiveViewingMode,
                actualImmersiveViewingMode: actualImmersiveViewingMode,
                desiredViewingMode: component.map { String(describing: $0.desiredViewingMode) },
                actualViewingMode: component?.viewingMode.map { String(describing: $0) },
                desiredSpatialVideoMode: desiredSpatialVideoMode,
                actualSpatialVideoMode: actualSpatialVideoMode
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
            playbackVideoSurfaceLogger.error(
                "surface attach failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private var entityID: String {
        #if os(macOS)
        "EnchronVideo.macOS#\(ObjectIdentifier(videoEntity))"
        #else
        "EnchronVideo.\(presentation)#\(ObjectIdentifier(videoEntity))"
        #endif
    }

    private var realityViewID: String {
        #if os(macOS)
        "EnchronRealityView.macOS#\(ObjectIdentifier(videoEntity))"
        #else
        "EnchronRealityView.\(presentation)#\(ObjectIdentifier(videoEntity))"
        #endif
    }

    private var component: VideoPlayerComponent? {
        videoEntity.components[VideoPlayerComponent.self]
    }

    private var desiredImmersiveViewingMode: String? {
        #if os(visionOS)
        component.map { String(describing: $0.desiredImmersiveViewingMode) }
        #else
        nil
        #endif
    }

    private var actualImmersiveViewingMode: String? {
        #if os(visionOS)
        component?.immersiveViewingMode.map { String(describing: $0) }
        #else
        nil
        #endif
    }

    private var desiredSpatialVideoMode: String? {
        #if os(visionOS)
        component.map { String(describing: $0.desiredSpatialVideoMode) }
        #else
        nil
        #endif
    }

    private var actualSpatialVideoMode: String? {
        #if os(visionOS)
        component.map { String(describing: $0.spatialVideoMode) }
        #else
        nil
        #endif
    }

    private var presentationPhase: PlaybackPresentationSettlementPhase {
        guard let component else { return .surfaceAttached }
        return component.currentRenderingStatus == .ready
            && component.viewingMode == component.desiredViewingMode
            ? .settled
            : .surfaceAttached
    }

    private func logComponentState(reason: String) {
        guard let component else { return }
        playbackVideoSurfaceLogger.notice(
            "component event=\(reason, privacy: .public) active=\(videoEntity.isActive) rendering=\(String(describing: component.currentRenderingStatus), privacy: .public)"
        )
        playbackVideoSurfaceLogger.notice(
            "component desiredViewing=\(String(describing: component.desiredViewingMode), privacy: .public) actualViewing=\(String(describing: component.viewingMode), privacy: .public)"
        )
        playbackVideoSurfaceLogger.notice(
            "component screenSize=\(String(describing: component.playerScreenSize), privacy: .public)"
        )
    }

    private func detachSurface() {
        playbackRuntime.detachSurface(entityID: entityID, realityViewID: realityViewID)
    }

    private func releaseSurface<Content: RealityViewContentProtocol>(from content: Content) {
        content.remove(videoEntity)
        releaseSurface()
    }

    private func releaseSurface() {
        surfaceActivation.cancel()
        componentObservation.cancel()
        subtitleSurface.remove()
        videoEntity.removeFromParent()
        videoEntity.components.remove(VideoPlayerComponent.self)
        playbackRuntime.releaseRendererConsumer(
            presentation: presentation,
            entityID: entityID
        )
        detachSurface()
    }

    private var activeSubtitleText: String? {
        let text = playbackRuntime.activeSubtitleCues
            .map(\.text)
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
