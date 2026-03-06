import SwiftUI
import RealityKit

public struct MainView: View {
    @Environment(AppModel.self) var appModel
    @Environment(WindowVideoViewModel.self) var windowVideoViewModel

    public init() {}

    public var body: some View {
        ZStack {
            AppTabView()

            if appModel.isPlaying && appModel.playbackMode == .window {
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

                    if appModel.showControls {
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
            }
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
                        // Controls visible + pinch outside controls area = hide all
                        withAnimation { appModel.showControls = false }
                        controlsTimerTask?.cancel()
                    } else {
                        // Controls hidden = show in initial state + restart timer
                        withAnimation { appModel.showControls = true }
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

            // Wire up playback ended callback
            windowVideoViewModel.onPlaybackEnded = {
                // Playback ended: stay on screen, show controls with play (replay) button
                withAnimation { appModel.showControls = true }
                controlsTimerTask?.cancel()
            }

            if appModel.isPlaying {
                startControlsTimer()
            }
        }
        .onChange(of: appModel.isPlaying) { _, isPlaying in
            if isPlaying {
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
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled, windowVideoViewModel.playbackState == .playing {
                withAnimation {
                    appModel.showControls = false
                }
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    MainView()
        .environment(AppModel())
}
