import RealityKit
import OSLog
import PlaybackCore
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
    private static let windowControlsAttachmentID = "Enchron.WindowPlaybackControls"
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
            RealityView { content, attachments in
                updateVisionSurface(
                    content,
                    attachments: attachments,
                    proxy: geometry,
                    revision: componentRevision
                )
            } update: { content, attachments in
                updateVisionSurface(
                    content,
                    attachments: attachments,
                    proxy: geometry,
                    revision: componentRevision
                )
            } attachments: {
                if presentation == .window {
                    Attachment(id: Self.windowControlsAttachmentID) {
                        WindowPlaybackControlPlane()
                    }
                }
            }
            .gesture(surfaceTapGesture)
            .frame(depth: 0)
        }
        .onDisappear {
            releaseSurface()
        }
    }
    #else
    private var macOSSurface: some View {
        ZStack {
            RealityView { content in
                await loadMacOSWorldIfNeeded()
                updateMacOSSurface(&content, revision: componentRevision)
            } update: { content in
                updateMacOSSurface(&content, revision: componentRevision)
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

                WindowPlaybackControlPlane()
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
        guard isActive, let renderer = playbackRuntime.renderer else {
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
        attachments: RealityViewAttachments,
        proxy: GeometryProxy3D,
        revision: Int
    ) {
        guard prepareSurface(in: content, revision: revision) else {
            setWindowControlsEnabled(false, attachments: attachments)
            return
        }
        let sceneSize = scaleToFitWindow(videoEntity, proxy: proxy, content: content)
        layoutWindowControls(
            attachments: attachments,
            content: content,
            sceneSize: sceneSize
        )
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
            : SIMD2<Float>(16.0 / 9.0, 1)
        let frame = proxy.frame(in: .local)
        let frameSize = abs(content.convert(frame.size, from: .local, to: .scene))
        let scale = min(
            Float(frameSize.x) / resolvedScreenSize.x,
            Float(frameSize.y) / resolvedScreenSize.y
        ) * 0.98
        guard scale.isFinite, scale > 0 else { return nil }
        entity.scale = .init(repeating: scale)
        let layoutSignature = "\(frameSize)-\(resolvedScreenSize)-\(scale)"
        if componentObservation.shouldLogLayout(layoutSignature) {
            playbackVideoSurfaceLogger.notice(
                "window layout sceneSize=\(String(describing: frameSize), privacy: .public) screenSize=\(String(describing: resolvedScreenSize), privacy: .public) scale=\(scale)"
            )
        }
        return frameSize
    }

    @MainActor
    private func layoutWindowControls(
        attachments: RealityViewAttachments,
        content: RealityViewContent,
        sceneSize: SIMD3<Float>?
    ) {
        guard presentation == .window,
              let controls = attachments.entity(for: Self.windowControlsAttachmentID),
              let sceneSize else { return }

        if content.entities.contains(where: { $0 === controls }) == false {
            content.add(controls)
        }

        controls.isEnabled = appModel.showControls && isActive
        let localBounds = controls.visualBounds(relativeTo: controls)
        guard localBounds.extents.x.isFinite, localBounds.extents.x > 0 else { return }

        let scale = sceneSize.x * 0.96 / localBounds.extents.x
        controls.scale = .init(repeating: scale)
        controls.position = [0, 0, 0.01]
    }

    @MainActor
    private func setWindowControlsEnabled(
        _ isEnabled: Bool,
        attachments: RealityViewAttachments
    ) {
        guard presentation == .window,
              let controls = attachments.entity(for: Self.windowControlsAttachmentID) else { return }
        controls.isEnabled = isEnabled
    }
    #else
    @MainActor
    private func updateMacOSSurface(
        _ content: inout RealityViewCameraContent,
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
            playbackRuntime.lastErrorMessage = macOSWorldLoadError
                ?? "The selected environment does not contain PlaybackSurfaceAnchor."
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
        case .docked:
            guard let macOSPlaybackSurfaceAnchor else { return }
            PlaybackSurfacePlacement.dock(
                videoEntity,
                to: macOSPlaybackSurfaceAnchor,
                transform: .init(
                    verticalOffset: appModel.screenVerticalOffset,
                    depthOffset: appModel.screenDepthOffset,
                    viewAngle: appModel.screenViewAngle,
                    scale: appModel.screenScale
                )
            )
        case .panorama:
            return
        }
        content.cameraTarget = videoEntity
        attachSurfaceIfReady()
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

    private var presentationPhase: String {
        guard let component else { return "surfaceAttached" }
        return component.currentRenderingStatus == .ready
            && component.viewingMode == component.desiredViewingMode
            ? "settled"
            : "surfaceAttached"
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

struct WindowPlaybackControlPlane: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    var body: some View {
        VStack(spacing: 0) {
            PlayerInfoBarView()
            Spacer(minLength: DesignTokens.Spacing.xl)
            WindowPlayerDeckView()
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 28)
        .frame(width: 1_000, height: 562.5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-window-control-plane")
        .accessibilityValue(playbackStateValue)
    }

    private var playbackStateValue: String {
        let position = playbackRuntime.playbackPosition
        return [
            "presentation=\(appModel.playbackPresentation.rawValue)",
            "attached=\(playbackRuntime.attachedPresentation?.rawValue ?? "none")",
            "lifecycle=\(playbackRuntime.lifecycle.label)",
            "session=\(playbackRuntime.activeSessionID ?? "none")",
            "position=\(position.seconds)",
            "duration=\(position.duration)",
            "subtitleTrack=\(playbackRuntime.currentSubtitleTrackID ?? "off")",
            "subtitleCues=\(playbackRuntime.activeSubtitleCues.count)"
        ].joined(separator: ";")
    }
}
