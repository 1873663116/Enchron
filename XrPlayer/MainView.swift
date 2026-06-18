import SwiftUI
import RealityKit
import UIKit

public struct MainView: View {
    @Environment(AppModel.self) var appModel
    @Environment(WindowVideoViewModel.self) var windowVideoViewModel
    @Environment(PlaybackLaunchCoordinator.self) var playbackLauncher
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(PanoramaLayerBridge.self) var panoramaBridge

    public init() {}

    private var isWindowPlaybackActive: Bool {
        appModel.isPlaying && appModel.playbackMode == .window
    }

    private var shouldShowPlayerControls: Bool {
        appModel.isPlaying && appModel.showControls && windowVideoViewModel.canPresentControls && appModel.playbackMode == .window
    }

    // MARK: - Load-failure retry (UC-PLAY-23)

    private func retryPlayback() {
        windowVideoViewModel.lastErrorMessage = nil
        guard let request = windowVideoViewModel.currentLaunchRequest else { return }
        playbackLauncher.beginPlayback(request)
    }

    public var body: some View {
        ZStack {
            // Content area — routed by navigation state.
            // Kept in tree (not removed via if/else) to preserve NavigationSplitView state.
            Group {
                switch appModel.selectedTab {
                case .files:
                    FilesScreen()
                case .settings:
                    SettingsScreen()
                case .environment:
                    // Environments opens a separate destination; the tab never parks
                    // here (see NavigationOrnament). Render nothing if ever reached.
                    Color.clear
                }
            }
            .opacity(isWindowPlaybackActive ? 0 : 1)
            .allowsHitTesting(!isWindowPlaybackActive)
            .accessibilityHidden(isWindowPlaybackActive)

            // Always-mounted video surface — hidden when not playing,
            // so attachVideoLayer() and native warmup complete before first play.
            ZStack(alignment: .topTrailing) {
                GeometryReader { geometry in
                    ZStack {
                        WindowVideoView(
                            viewModel: windowVideoViewModel,
                            containerSize: geometry.size
                        )
                        .opacity(shouldShowMPVSurface ? 1 : 0)

                        if shouldShowAppleReferenceSurface {
                            AppleReferenceVideoSurface(player: windowVideoViewModel.appleReferencePlayer)
                                .background(.black)
                        }
                    }
                }
                .glassBackgroundEffect()
                // Edge vignette — darkens screen edges when controls are visible
                // so labels remain readable against bright/white video content.
                // Placed on GeometryReader (same frame as glass background) so it
                // naturally clips to the window's rounded corners.
                .overlay {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.black.opacity(0.65), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 160)
                        Spacer()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 200)
                    }
                    .clipShape(DesignTokens.ShapeToken.panel)
                    .opacity(appModel.showControls && appModel.isPlaying ? 1 : 0)
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !pinchBegan {
                                    pinchBegan = true
                                    windowVideoViewModel.gestureUseCase.handlePinchBegan()
                                } else {
                                    windowVideoViewModel.gestureUseCase.handlePinchChanged(
                                        translation: value.translation
                                    )
                                }
                            }
                            .onEnded { _ in
                                pinchBegan = false
                                windowVideoViewModel.gestureUseCase.handlePinchEnded()
                            }
                    )

                if windowVideoViewModel.presentationState != .videoVisible {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(.black)
                        .transition(.opacity)
                }

                if windowVideoViewModel.presentationState == .placeholder {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
                        .transition(.opacity)
                }

                if windowVideoViewModel.playbackState == .buffering {
                    ProgressView("Buffering…")
                        .progressViewStyle(.circular)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
                        .transition(.opacity)
                }

            }
            // Info bar overlay (top-leading)
            .overlay(alignment: .topLeading) {
                if appModel.showControls && appModel.isPlaying && appModel.playbackMode == .window {
                    PlayerInfoBarView()
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .transition(.opacity)
                }
            }
            // Load-failure panel (UC-PLAY-23) — polished glass card over the
            // darkened video, replaces the system error alert.
            .overlay {
                if isWindowPlaybackActive, let message = windowVideoViewModel.lastErrorMessage {
                    PlaybackOverlayCard(
                        systemImage: "exclamationmark.triangle",
                        title: "Failed to Load",
                        message: message,
                        primaryTitle: "Retry",
                        primaryIcon: "arrow.clockwise",
                        primaryAction: { retryPlayback() },
                        secondaryTitle: "Close",
                        secondaryIcon: "xmark",
                        secondaryAction: {
                            windowVideoViewModel.lastErrorMessage = nil
                            playbackLauncher.stopPlayback()
                        },
                        identifierPrefix: "PlayerUI-loadFailure"
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: appModel.showControls)
            .opacity(isWindowPlaybackActive ? 1 : 0)
            .scaleEffect(isWindowPlaybackActive ? 1.0 : 0.98)
            .blur(radius: isWindowPlaybackActive ? 0 : 4)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appModel.isPlaying)
            .allowsHitTesting(isWindowPlaybackActive)
            .accessibilityHidden(!isWindowPlaybackActive)
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            // Polished player deck (transport / progress / precision timeline /
            // ⋯ menu) driven by WindowVideoViewModel — replaces PlayerControlsView.
            WindowPlayerDeckView()
                .opacity(shouldShowPlayerControls ? 1 : 0)
                .allowsHitTesting(shouldShowPlayerControls)
        }
        .ornament(
            visibility: appModel.isPlaying ? .hidden : .visible,
            attachmentAnchor: .scene(.leading),
            contentAlignment: .trailing
        ) {
            NavigationOrnament()
        }
        // Leading playback-settings panel (Environment / Play Mode / Picture),
        // summoned by the deck's ≡ button — replaces SettingsPopoverContent.
        .ornament(
            visibility: (shouldShowPlayerControls && appModel.showPlayerSettingsPopup) ? .visible : .hidden,
            attachmentAnchor: .scene(.leading),
            contentAlignment: .trailing
        ) {
            PlaybackSettingsPanel()
                .opacity(shouldShowPlayerControls && appModel.showPlayerSettingsPopup ? 1 : 0)
                .allowsHitTesting(shouldShowPlayerControls && appModel.showPlayerSettingsPopup)
        }
        .sheet(isPresented: Bindable(appModel).showSceneSelector) {
            SceneSelectorView()
        }
        .onAppear {
            windowVideoViewModel.gestureUseCase.onGestureResolved = { gesture in
                switch gesture {
                case .singlePinch:
                    if appModel.showControls {
                        guard appModel.isControlsFocused == false else {
                            appModel.registerControlsInteraction()
                            break
                        }
                        withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = false }
                        controlsTimerTask?.cancel()
                    } else {
                        withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
                        appModel.registerControlsInteraction()
                        startControlsTimer()
                    }
                case .doublePinch:
                    if windowVideoViewModel.playbackState == .playing {
                        windowVideoViewModel.pause()
                    } else if windowVideoViewModel.playbackState == .ended {
                        windowVideoViewModel.replay()
                    } else {
                        windowVideoViewModel.resume()
                    }
                case .drag:
                    seekStartSeconds = windowVideoViewModel.playbackPosition.seconds
                    if !appModel.showControls {
                        withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
                        appModel.registerControlsInteraction()
                        startControlsTimer()
                    }
                case .longPress:
                    break
                }
            }

            windowVideoViewModel.gestureUseCase.onLongPressBegan = {
                speedBeforeLongPress = appModel.playbackSpeed
                windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(2.0))
            }
            windowVideoViewModel.gestureUseCase.onLongPressEnded = {
                windowVideoViewModel.setSpeed(speedBeforeLongPress ?? .default)
                speedBeforeLongPress = nil
            }

            windowVideoViewModel.gestureUseCase.onDragUpdate = { translation in
                guard let startPos = seekStartSeconds else { return }
                let duration = windowVideoViewModel.playbackPosition.duration
                guard duration > 0 else { return }
                let seekDelta = Double(translation.width) * 0.15
                let target = max(0, min(duration, startPos + seekDelta))
                windowVideoViewModel.seek(to: target)
                appModel.registerControlsInteraction()
            }
            windowVideoViewModel.gestureUseCase.onDragEnded = {
                seekStartSeconds = nil
            }

            windowVideoViewModel.onPlaybackEnded = {
                let shouldShowControls = playbackLauncher.handlePlaybackEnded(
                    onFallbackShowControls: {
                        withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
                        controlsTimerTask?.cancel()
                    }
                )
                if shouldShowControls {
                    withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
                    controlsTimerTask?.cancel()
                }
            }

            if appModel.isPlaying {
                startControlsTimer()
            }
        }
        .onChange(of: appModel.isPlaying) { _, isPlaying in
            if isPlaying {
                appModel.registerControlsInteraction()
                withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
                startControlsTimer()
            }
            updateWindowResizingRestrictions(isPlaying: isPlaying)
        }
        .onChange(of: appModel.playbackMode) { oldMode, newMode in
            guard appModel.isPlaying else { return }
            let needsImmersive = newMode == .panorama || newMode == .immersive
            let oldNeedsImmersive = oldMode == .panorama || oldMode == .immersive
            // Only transition when immersive requirement actually changes
            guard needsImmersive != oldNeedsImmersive else { return }
            Task { @MainActor in
                // Detach panorama bridge before dismissing old immersive space
                if oldNeedsImmersive {
                    panoramaBridge.attachVideoLayer(nil)
                }

                if needsImmersive && appModel.immersiveSpaceState == .closed {
                    await openImmersiveSpaceUnified()
                } else if !needsImmersive && appModel.immersiveSpaceState == .open {
                    appModel.isTransitioningPlaybackMode = true
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    openWindow(id: "main")
                    appModel.isTransitioningPlaybackMode = false
                }
            }
        }
        .onChange(of: appModel.immersiveSpaceRequest) { _, request in
            // Unified entry point for sub-views (SceneSelectorView, ToggleImmersiveSpaceButton)
            // that cannot call openImmersiveSpace directly per Architecture Invariant.
            guard let request else { return }
            appModel.immersiveSpaceRequest = nil
            Task { @MainActor in
                switch request {
                case .open:
                    await openImmersiveSpaceUnified()
                case .dismiss:
                    guard appModel.immersiveSpaceState == .open else { return }
                    appModel.isTransitioningPlaybackMode = true
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                    openWindow(id: "main")
                    dismissWindow(id: "playerControls")
                    appModel.isTransitioningPlaybackMode = false
                }
            }
        }
        .onChange(of: appModel.playbackMode != .window) { _, shouldShow in
            // P1 #1 fix: serialize window operations to prevent race on rapid mode transitions.
            // §5.9d: removed isPlaying gate — paused state can also summon controls.
            guard !appModel.isTransitioningPlaybackMode else { return }
            playerControlsWindowTask?.cancel()
            playerControlsWindowTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                if shouldShow {
                    openWindow(id: "playerControls")
                } else {
                    dismissWindow(id: "playerControls")
                }
            }
        }
    }

    private var shouldShowMPVSurface: Bool {
        DiagnosticsFeatureFlags.hdrLabEnabled == false || windowVideoViewModel.diagnosticRenderer == .mpv
    }

    private var shouldShowAppleReferenceSurface: Bool {
        DiagnosticsFeatureFlags.hdrLabEnabled && windowVideoViewModel.diagnosticRenderer == .apple
    }

    // MARK: - Unified Immersive Space Entry (§5.9a)

    /// Single canonical site where openImmersiveSpace is called.
    /// All sub-views route through appModel.immersiveSpaceRequest,
    /// which is observed here and dispatched to this function.
    @MainActor
    private func openImmersiveSpaceUnified() async {
        appModel.isTransitioningPlaybackMode = true
        appModel.immersiveSpaceState = .inTransition
        appModel.isFullImmersion = true   // §5.9c: ensure full/exclusive immersion on every entry
        switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
        case .opened:
            // Attach video layer for panorama/immersive rendering
            let layer = windowVideoViewModel.nativeVideoLayer
            panoramaBridge.attachVideoLayer(layer)
            // §5.9b: mark state as open before dismissing main window
            appModel.immersiveSpaceState = .open
            dismissWindow(id: "main")
        case .userCancelled, .error:
            fallthrough
        @unknown default:
            // §5.9b: keep main window visible on failure
            appModel.immersiveSpaceState = .closed
            appModel.updatePlaybackMode(.window)
        }
        appModel.isTransitioningPlaybackMode = false
    }

    @State private var controlsTimerTask: Task<Void, Never>?
    @State private var playerControlsWindowTask: Task<Void, Never>?
    @State private var pinchBegan = false
    @State private var speedBeforeLongPress: PlaybackCoreDomain.PlaybackSpeed?
    @State private var seekStartSeconds: Double?

    /// Switches visionOS window resizing between uniform (aspect-ratio-locked)
    /// during playback and freeform when browsing files.
    /// Uses Apple's `UIWindowScene.GeometryPreferences.Vision` API.
    private func updateWindowResizingRestrictions(isPlaying: Bool) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else { return }
        let restrictions: UIWindowScene.ResizingRestrictions = isPlaying ? .uniform : .freeform
        windowScene.requestGeometryUpdate(
            .Vision(resizingRestrictions: restrictions)
        )
    }

    private func startControlsTimer() {
        controlsTimerTask?.cancel()
        controlsTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard windowVideoViewModel.playbackState == .playing else { continue }
                guard appModel.canAutoHideControls else { continue }

                let idleTime = Date().timeIntervalSince(appModel.lastControlsInteractionAt)
                if idleTime >= 8 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        appModel.showControls = false
                    }
                    return
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    let appModel = AppModel()
    let windowVideoViewModel = WindowVideoViewModel(player: MPVPlayerAdapter())
    let launcher = PlaybackLaunchCoordinator(
        appModel: appModel,
        windowVideoViewModel: windowVideoViewModel
    )
    let fileBrowsingViewModel = FileBrowsingViewModel(localDataSource: LocalDataSourceAdapter()) { request in
        launcher.beginPlayback(request)
    }

    MainView()
        .environment(appModel)
        .environment(windowVideoViewModel)
        .environment(fileBrowsingViewModel)
        .environment(launcher)
        .environment(PanoramaLayerBridge())
        .environment(ThumbnailService.shared)
}
