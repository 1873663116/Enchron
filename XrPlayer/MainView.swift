import SwiftUI
import RealityKit

public struct MainView: View {
    @Environment(AppModel.self) var appModel
    @Environment(WindowVideoViewModel.self) var windowVideoViewModel
    @Environment(PlaybackLaunchCoordinator.self) var playbackLauncher

    public init() {}

    public var body: some View {
        ZStack {
            AppTabView()

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
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.black)
                        .transition(.opacity)
                }

                if windowVideoViewModel.presentationState == .placeholder {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                }

                if appModel.showControls && appModel.isPlaying {
                    Button {
                        playbackLauncher.stopPlayback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.bold)) // Thicker icon for better clarity at smaller size
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PlayerControlSurfaceStyle(size: 48)) // Refined, more elegant size
                    .padding(24)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: .offset(y: -10)),
                        removal: .opacity.combined(with: .scale(scale: 0.8))
                    ))
                }
            }
            .padding()
            .opacity(appModel.isPlaying && appModel.playbackMode == .window ? 1 : 0)
            .scaleEffect(appModel.isPlaying && appModel.playbackMode == .window ? 1.0 : 0.98) // Added focus-in effect
            .blur(radius: appModel.isPlaying && appModel.playbackMode == .window ? 0 : 4) // Added soft reveal
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appModel.isPlaying)
            .allowsHitTesting(appModel.isPlaying && appModel.playbackMode == .window)
            .accessibilityHidden(!(appModel.isPlaying && appModel.playbackMode == .window))
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
            if appModel.isPlaying && appModel.showControls && windowVideoViewModel.canPresentControls {
                PlayerControlsView()
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.92, anchor: .bottom))
                                .combined(with: .offset(y: 20)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.95, anchor: .bottom))
                                .combined(with: .offset(y: 10))
                        )
                    )
            }
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
                case .longPress, .drag:
                    break
                }
            }

            windowVideoViewModel.gestureUseCase.onLongPressBegan = {
                windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(2.0))
            }
            windowVideoViewModel.gestureUseCase.onLongPressEnded = {
                windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(1.0))
            }

            windowVideoViewModel.onPlaybackEnded = {
                withAnimation { appModel.showControls = true }
                controlsTimerTask?.cancel()
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
    }

    @State private var controlsTimerTask: Task<Void, Never>?
    @State private var pinchBegan = false

    private func startControlsTimer() {
        controlsTimerTask?.cancel()
        controlsTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                guard windowVideoViewModel.playbackState == .playing else { continue }
                guard appModel.canAutoHideControls else { continue }

                let idleTime = Date().timeIntervalSince(appModel.lastControlsInteractionAt)
                if idleTime >= 3 {
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
}
