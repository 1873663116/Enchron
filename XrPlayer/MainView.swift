import SwiftUI
import RealityKit

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

    public var body: some View {
        ZStack {
            // Content area — routed by navigation state.
            // Kept in tree (not removed via if/else) to preserve NavigationSplitView state.
            Group {
                switch appModel.selectedTab {
                case .browse:
                    FileBrowserView()
                case .recent:
                    RecentlyPlayedView()
                case .settings:
                    SettingsView()
                }
            }
            .opacity(isWindowPlaybackActive ? 0 : 1)
            .allowsHitTesting(!isWindowPlaybackActive)
            .accessibilityHidden(isWindowPlaybackActive)

            // Always-mounted video surface — hidden when not playing,
            // so attachVideoLayer() and native warmup complete before first play.
            ZStack(alignment: .topTrailing) {
                WindowVideoView(viewModel: windowVideoViewModel)
                    .glassBackgroundEffect()
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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge))
                        .transition(.opacity)
                }

                if windowVideoViewModel.playbackState == .buffering {
                    ProgressView("Buffering…")
                        .progressViewStyle(.circular)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.badge))
                        .transition(.opacity)
                }

                if appModel.showControls && appModel.isPlaying {
                    Button {
                        playbackLauncher.stopPlayback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PlayerControlSurfaceStyle(size: 48))
                    .padding(24)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .offset(y: -10)),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    ))
                }
            }
            .opacity(isWindowPlaybackActive ? 1 : 0)
            .scaleEffect(isWindowPlaybackActive ? 1.0 : 0.98)
            .blur(radius: isWindowPlaybackActive ? 0 : 4)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appModel.isPlaying)
            .allowsHitTesting(isWindowPlaybackActive)
            .accessibilityHidden(!isWindowPlaybackActive)
        }
        .alert(
            "Playback Error",
            isPresented: Binding(
                get: { windowVideoViewModel.lastErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        windowVideoViewModel.lastErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                windowVideoViewModel.lastErrorMessage = nil
            }
        } message: {
            Text(windowVideoViewModel.lastErrorMessage ?? "Unknown playback error")
        }
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .center) {
            Group {
                if appModel.isPlaying && appModel.showControls && windowVideoViewModel.canPresentControls && appModel.playbackMode == .window {
                    PlayerControlsView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: appModel.showControls)
            .animation(.easeInOut(duration: 0.4), value: appModel.isPlaying)
        }
        .ornament(
            visibility: appModel.isPlaying ? .hidden : .visible,
            attachmentAnchor: .scene(.leading),
            contentAlignment: .trailing
        ) {
            NavigationOrnament()
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
                        withAnimation { appModel.showControls = false }
                        controlsTimerTask?.cancel()
                    } else {
                        withAnimation { appModel.showControls = true }
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
                        withAnimation { appModel.showControls = true }
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
                        withAnimation { appModel.showControls = true }
                        controlsTimerTask?.cancel()
                    }
                )
                if shouldShowControls {
                    withAnimation { appModel.showControls = true }
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
                appModel.showControls = true
                startControlsTimer()
            }
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
                    appModel.immersiveSpaceState = .inTransition
                    switch await openImmersiveSpace(id: appModel.immersiveSpaceID) {
                    case .opened:
                        // Attach video layer for panorama/immersive rendering
                        let layer = windowVideoViewModel.nativeVideoLayer
                        panoramaBridge.attachVideoLayer(layer)
                    case .userCancelled, .error:
                        fallthrough
                    @unknown default:
                        appModel.immersiveSpaceState = .closed
                        appModel.updatePlaybackMode(.window)
                    }
                } else if !needsImmersive && appModel.immersiveSpaceState == .open {
                    appModel.immersiveSpaceState = .inTransition
                    await dismissImmersiveSpace()
                }
            }
        }
        .onChange(of: appModel.playbackMode != .window && appModel.isPlaying) { _, shouldShow in
            // P1 #1 fix: serialize window operations to prevent race on rapid mode transitions
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

    @State private var controlsTimerTask: Task<Void, Never>?
    @State private var playerControlsWindowTask: Task<Void, Never>?
    @State private var pinchBegan = false
    @State private var speedBeforeLongPress: PlaybackCoreDomain.PlaybackSpeed?
    @State private var seekStartSeconds: Double?

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
                    withAnimation {
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
}
