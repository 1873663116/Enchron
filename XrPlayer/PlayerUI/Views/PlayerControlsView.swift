import SwiftUI

/// Player controls following the 2-tier layout from player.html footer:
///
/// Tier 1: Seek bar (current time | progress track | remaining time)
/// Tier 2: Control bar pill (Menu | Rew | Play | Fwd | Settings)
///
/// Info bar (PlayerInfoBarView) lives in MainView's video ZStack overlay.
/// Below: expandable NLE timeline panel.
///
/// Menu panels are rendered in the WINDOW space (MainView overlay),
/// not inside this ornament — visionOS ornaments clip content at their bounds.
/// Button actions toggle AppModel menu state; MainView reads it for display.
public struct PlayerControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(\.openWindow) private var openWindow

    @State private var showScreenPositionSheet = false
    @State private var showDebugSheet = false
    @State private var lastInteractionTime = Date()
    @State private var hasAppliedSmokePanelRequest = false
    @State private var isTimelineExpanded = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // ── Tier 1: Seek bar ──
            SeekBarView(
                isTimelineExpanded: $isTimelineExpanded,
                onInteraction: registerInteraction
            )
            .padding(.horizontal, 48)
            .opacity(isTimelineExpanded ? 0.3 : 1.0)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: isTimelineExpanded)

            // ── Tier 2: Control bar pill (buttons only, no menu panels) ──
            controlBarPill

            // ── Tier 3: NLE Timeline ──
            NLETimelineView(
                isExpanded: $isTimelineExpanded,
                onSeek: { videoViewModel.seek(to: $0) },
                onFrameStepForward: { videoViewModel.frameStepForward() },
                onFrameStepBackward: { videoViewModel.frameStepBackward() }
            )
        }
        .frame(width: DesignTokens.Layout.playerControlsWidth)
        .onHover { isHovering in
            appModel.setControlsFocused(isHovering)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    registerInteraction()
                }
        )
        .onChange(of: appModel.currentPlaybackURL) { _, _ in
            registerInteraction()
        }
        .task(id: lastInteractionTime) {
            do {
                try await Task.sleep(for: .seconds(8))
                guard !appModel.isControlsFocused else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    appModel.showControls = false
                }
            } catch {}
        }
        .task(id: appModel.smokePanelRequest) {
            await applySmokePanelRequestIfNeeded()
        }
        // Close all menus when controls auto-hide
        .onChange(of: appModel.showControls) { _, visible in
            if !visible {
                appModel.closeAllPlayerMenus()
            }
        }
        .sheet(isPresented: $showScreenPositionSheet) {
            ScreenPositionControlView {
                showScreenPositionSheet = false
            }
            .frame(width: 380, height: 420)
        }
        .sheet(isPresented: $showDebugSheet) {
            DebugOverlayView {
                showDebugSheet = false
            }
            .frame(width: 380, height: 480)
        }
    }

    // MARK: - Control Bar Pill (pure buttons, no menu panels)

    @ViewBuilder
    private var controlBarPill: some View {
        HStack(spacing: 8) {
            // ── Left: Menu button ──
            Button {
                registerInteraction()
                appModel.showPlayerSettingsPopup = false
                appModel.playerSettingsSubMenu = nil
                appModel.playerMenuSubMenu = nil
                appModel.showPlayerMenuPopup.toggle()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .help("Playback Options")
            .accessibilityIdentifier("left-menu-button")
            .accessibilityLabel("Playback Options")

            // ── Rewind 10s ──
            Button {
                videoViewModel.skip(by: -10)
                registerInteraction()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .help("Backward 10s")
            .accessibilityIdentifier("rewind-button")
            .accessibilityLabel("Rewind 10 seconds")

            // ── Play / Pause ──
            Button {
                if videoViewModel.playbackState == .ended {
                    videoViewModel.replay()
                } else if videoViewModel.playbackState == .playing {
                    videoViewModel.pause()
                } else {
                    videoViewModel.resume()
                }
                registerInteraction()
            } label: {
                Image(systemName: playButtonIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color(red: 0.184, green: 0.192, blue: 0.192))
                    .frame(width: 64, height: 64)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.776, green: 0.776, blue: 0.780),
                                Color(red: 0.565, green: 0.569, blue: 0.569),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .padding(.horizontal, 8)
            .accessibilityIdentifier("play-pause-button")
            .accessibilityLabel(playButtonAccessibilityLabel)

            // ── Forward 10s ──
            Button {
                videoViewModel.skip(by: 10)
                registerInteraction()
            } label: {
                Image(systemName: "goforward.10")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .help("Forward 10s")
            .accessibilityIdentifier("forward-button")
            .accessibilityLabel("Forward 10 seconds")

            // ── Right: Settings button ──
            Button {
                registerInteraction()
                appModel.showPlayerMenuPopup = false
                appModel.playerMenuSubMenu = nil
                appModel.playerSettingsSubMenu = nil
                appModel.showPlayerSettingsPopup.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .help("Settings")
            .accessibilityIdentifier("right-menu-button")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .enchronGlassControl()
    }

    // MARK: - Playback State Helpers

    private var playButtonIcon: String {
        switch videoViewModel.playbackState {
        case .playing:
            return "pause.fill"
        case .ended:
            return "arrow.counterclockwise"
        default:
            return "play.fill"
        }
    }

    private var playButtonAccessibilityLabel: String {
        switch videoViewModel.playbackState {
        case .playing:
            return "Pause"
        case .ended:
            return "Replay"
        default:
            return "Play"
        }
    }

    // MARK: - Interaction & Auto-Hide

    private func registerInteraction() {
        lastInteractionTime = Date()
        appModel.registerControlsInteraction()
        if appModel.showControls == false {
            withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
        }
    }

    @MainActor
    private func applySmokePanelRequestIfNeeded() async {
        guard hasAppliedSmokePanelRequest == false,
            appModel.smokePanelRequest != nil
        else {
            return
        }

        hasAppliedSmokePanelRequest = true
        appModel.showControls = true
    }
}

// MARK: - SeekBarView
//
// Isolated sub-view that owns all reads of `videoViewModel.playbackPosition`.
// Because SwiftUI invalidates only the view that reads a changed @Observable
// property, confining playbackPosition here prevents the 200ms polling loop
// from re-evaluating PlayerControlsView.controlBarPill (and its menus).
private struct SeekBarView: View {
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Binding var isTimelineExpanded: Bool
    let onInteraction: () -> Void

    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                // Current time (left)
                Text(
                    PlaybackTimeFormatter.clock(
                        isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds)
                )
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: {
                            isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds
                        },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(videoViewModel.playbackPosition.duration, 1),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if editing {
                            onInteraction()
                        }
                        if !editing {
                            videoViewModel.seek(to: dragValue)
                        }
                    }
                )
                .tint(.white)
                .frame(minHeight: 44)
                // Double-tap on seek bar toggles NLE timeline (player.html:1183)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        isTimelineExpanded.toggle()
                    }
                }
                .accessibilityIdentifier("PlayerUI-SeekBar-slider-position")
                .accessibilityLabel("Playback position")
                .accessibilityValue(
                    "\(PlaybackTimeFormatter.clock(isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds)) of \(PlaybackTimeFormatter.clock(videoViewModel.playbackPosition.duration))"
                )

                // Remaining time (right, countdown with minus prefix)
                Text(remainingTimeLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
            }

            // Precision time during drag
            if isDraggingSlider {
                Text(
                    PlaybackTimeFormatter.preciseClock(
                        dragValue,
                        framesPerSecond: videoViewModel.displayMediaProfile?.frameRate ?? 0
                    )
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange)
                .transition(.opacity)
            }
        }
    }

    private var remainingTimeLabel: String {
        let duration = videoViewModel.playbackPosition.duration
        let current = isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds
        let remaining = max(0, duration - current)
        return "-" + PlaybackTimeFormatter.clock(remaining)
    }
}

#Preview {
    let appModel = AppModel()
    let windowVideoViewModel = WindowVideoViewModel(player: MPVPlayerAdapter())

    PlayerControlsView()
        .environment(appModel)
        .environment(windowVideoViewModel)
}
