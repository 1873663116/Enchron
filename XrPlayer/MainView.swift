import SwiftUI
import RealityKit

public struct MainView: View {
    @Environment(AppModel.self) var appModel
    @Environment(WindowVideoViewModel.self) var windowVideoViewModel

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

                // Loading indicator — shown during initial file open (black-screen period).
                if windowVideoViewModel.playbackState == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .transition(.opacity)
                }

                if appModel.showControls && appModel.isPlaying {
                    Button {
                        windowVideoViewModel.stop()
                        appModel.stopPlayback()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                    .transition(.opacity)
                }
            }
            .padding()
            .opacity(appModel.isPlaying && appModel.playbackMode == .window ? 1 : 0)
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
            if appModel.isPlaying && appModel.showControls {
                PlayerControlsView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
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
    MainView()
        .environment(AppModel())
}
