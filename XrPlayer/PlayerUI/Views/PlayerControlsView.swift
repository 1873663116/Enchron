import SwiftUI

/// Player controls following the 2-tier layout from player.html footer:
///
/// Tier 1: Seek bar (current time | progress track | remaining time)
/// Tier 2: Control bar pill (Menu | Rew | Play | Fwd | NLE toggle | Settings)
///
/// Info bar (PlayerInfoBarView) lives in MainView's video ZStack overlay.
/// Below: expandable NLE timeline panel
public struct PlayerControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(PlaybackLaunchCoordinator.self) private var launcher
    @Environment(\.openWindow) private var openWindow

    @State private var showScreenPositionSheet = false
    @State private var showDebugSheet = false
    @State private var lastInteractionTime = Date()
    @State private var hasAppliedSmokePanelRequest = false
    @State private var isTimelineExpanded = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // ── Tier 1: Seek bar (above pill, no glass) ──
            // Isolated into SeekBarView so that 200ms playbackPosition polling
            // only invalidates SeekBarView — not controlBarPill (leftMenu/rightMenu).
            SeekBarView(onInteraction: registerInteraction)
                .padding(.horizontal, 28)

            // ── Tier 2: Control bar pill (glass capsule) ──
            controlBarPill

            // ── NLE Timeline panel (expands below pill) ──
            NLETimelineView(
                isExpanded: $isTimelineExpanded,
                currentTime: videoViewModel.playbackPosition.seconds,
                duration: videoViewModel.playbackPosition.duration,
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

    // MARK: - Tier 3: Control Bar Pill

    @ViewBuilder
    private var controlBarPill: some View {
        HStack(spacing: 8) {
            // ── Left: Menu (popup expands upward) ──
            leftMenu

            // ── Rewind 10s ──
            Button {
                videoViewModel.skip(by: -10)
                registerInteraction()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .frame(width: 48, height: 48)
            .contentShape(.circle)
            .help("Backward 10s")

            // ── Play / Pause (larger, gradient background per player.html) ──
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
            }
            .buttonStyle(.plain)
            .frame(width: 64, height: 64)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.776, green: 0.776, blue: 0.780),  // #c6c6c7
                        Color(red: 0.565, green: 0.569, blue: 0.569),  // #909191
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(.circle)
            .contentShape(.circle)
            .hoverEffect(.lift)
            .accessibilityLabel(playButtonAccessibilityLabel)

            // ── Forward 10s ──
            Button {
                videoViewModel.skip(by: 10)
                registerInteraction()
            } label: {
                Image(systemName: "goforward.10")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .frame(width: 48, height: 48)
            .contentShape(.circle)
            .help("Forward 10s")

            // ── NLE Timeline toggle ──
            NLETimelineToggleButton(isExpanded: $isTimelineExpanded)

            // ── Right: Settings menu (popup expands upward) ──
            rightMenu
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .enchronGlassControl()
    }

    // MARK: - Left Menu (Playback Options)

    private var leftMenu: some View {
        Menu {
            // HDR toggle (only if content is HDR) — matches HTML top position
            if videoViewModel.isHDRContent {
                Section("Video Output") {
                    Toggle(
                        "HDR Output",
                        isOn: Binding(
                            get: { videoViewModel.isHDROutputEnabled },
                            set: { videoViewModel.setHDREnabled($0) }
                        )
                    )
                }
            }

            // Subtitles
            Section("Subtitles") {
                Picker("Subtitles", selection: subtitleBinding) {
                    Text("Off").tag("no" as String)
                    ForEach(videoViewModel.availableSubtitleTracks) { track in
                        Text(track.displayName).tag(track.id)
                    }
                }
            }

            // Audio tracks
            Section("Audio") {
                Picker("Audio Track", selection: audioTrackBinding) {
                    ForEach(videoViewModel.availableAudioTracks) { track in
                        Text(track.displayName).tag(track.id)
                    }
                }
            }

            // Playback Speed
            Section("Speed") {
                Picker("Speed", selection: speedBinding) {
                    ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.self) { speed in
                        Text(speedLabel(speed)).tag(speed)
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .help("Playback Options")
        .accessibilityLabel("Playback Options")
    }

    // MARK: - Right Menu (Settings)

    private var rightMenu: some View {
        Menu {
            // Playback mode (filtered by geometric constraint)
            Section("Mode") {
                let allowed = DecidePlaybackModeUseCase.allowedModes(
                    for: appModel.effectiveProjectionType
                )
                ForEach(PlaybackMode.allCases.filter { allowed.contains($0) }, id: \.self) { mode in
                    Button {
                        switchPlaybackMode(to: mode)
                    } label: {
                        if appModel.playbackMode == mode {
                            Label(playbackModeLabel(mode), systemImage: "checkmark")
                        } else {
                            Label(playbackModeLabel(mode), systemImage: playbackModeIcon(mode))
                        }
                    }
                    .disabled(
                        mode == appModel.playbackMode
                            || appModel.immersiveSpaceState == .inTransition)
                }
            }

            // Projection
            Section("Projection") {
                Button {
                    appModel.setProjectionOverride(nil)
                } label: {
                    if appModel.projectionOverride == nil {
                        Label(
                            "Auto (\(projectionLabel(appModel.detectedProjectionType)))",
                            systemImage: "checkmark")
                    } else {
                        Text("Auto (\(projectionLabel(appModel.detectedProjectionType)))")
                    }
                }

                ForEach(PlaybackCoreDomain.ProjectionType.allCases, id: \.self) { type in
                    Button {
                        appModel.setProjectionOverride(type)
                    } label: {
                        if appModel.projectionOverride == type {
                            Label(projectionLabel(type), systemImage: "checkmark")
                        } else {
                            Text(projectionLabel(type))
                        }
                    }
                }
            }

            // Environment (cinema environment) — only in immersive
            if appModel.immersiveSpaceState == .open {
                Section("Environment") {
                    ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) {
                        environment in
                        Button {
                            Task {
                                await appModel.switchEnvironment(to: environment)
                            }
                        } label: {
                            if appModel.currentCinemaEnvironment == environment {
                                Label(environment.displayName, systemImage: "checkmark")
                            } else {
                                Text(environment.displayName)
                            }
                        }
                    }
                }

                Button {
                    registerInteraction()
                    showScreenPositionSheet = true
                } label: {
                    Label("Screen Position", systemImage: "move.3d")
                }
            }

            Divider()

            // Playlist
            Section("Playlist") {
                if fileBrowsingViewModel.files.isEmpty {
                    Text("No playlist items")
                } else {
                    ForEach(fileBrowsingViewModel.files, id: \.id) { file in
                        Button {
                            Task {
                                do {
                                    let request = try await fileBrowsingViewModel.playbackRequest(
                                        for: file)
                                    await MainActor.run {
                                        launcher.beginPlayback(request)
                                    }
                                } catch {
                                    await MainActor.run {
                                        fileBrowsingViewModel.lastErrorMessage =
                                            "Failed to open \"\(file.name)\": \(error.localizedDescription)"
                                    }
                                }
                            }
                        } label: {
                            if appModel.currentPlaybackURL?.lastPathComponent == file.name {
                                Label(file.name, systemImage: "checkmark")
                            } else {
                                Text(file.name)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                openWindow(id: "settings")
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            #if DEBUG
                Button {
                    registerInteraction()
                    showDebugSheet = true
                } label: {
                    Label("Debug", systemImage: "ladybug")
                }
            #endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    // MARK: - Bindings for Pickers

    private var speedBinding: Binding<PlaybackCoreDomain.PlaybackSpeed> {
        Binding(
            get: { appModel.playbackSpeed },
            set: { speed in
                videoViewModel.setSpeed(speed)
                appModel.updatePlaybackSpeed(speed)
            }
        )
    }

    private var subtitleBinding: Binding<String> {
        Binding(
            get: {
                videoViewModel.currentSubtitleTrackID ?? "no"
            },
            set: { trackID in
                if trackID == "no" {
                    videoViewModel.selectSubtitleTrack(nil)
                } else {
                    let track = videoViewModel.availableSubtitleTracks.first { $0.id == trackID }
                    videoViewModel.selectSubtitleTrack(track)
                }
            }
        )
    }

    private var audioTrackBinding: Binding<String> {
        Binding(
            get: {
                videoViewModel.currentAudioTrackID ?? ""
            },
            set: { trackID in
                let track = videoViewModel.availableAudioTracks.first { $0.id == trackID }
                if let track {
                    videoViewModel.selectAudioTrack(track)
                }
            }
        )
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

    // MARK: - Mode Switching

    private func switchPlaybackMode(to mode: PlaybackMode) {
        guard mode != appModel.playbackMode else { return }
        guard appModel.immersiveSpaceState != .inTransition else { return }
        appModel.updatePlaybackMode(mode)
    }

    // MARK: - Label Helpers

    private func playbackModeLabel(_ mode: PlaybackMode) -> String {
        switch mode {
        case .window: return "Window"
        case .immersive: return "Immersive"
        case .panorama: return "Panorama"
        }
    }

    private func playbackModeIcon(_ mode: PlaybackMode) -> String {
        switch mode {
        case .window: return "rectangle.inset.filled"
        case .immersive: return "visionpro"
        case .panorama: return "pano"
        }
    }

    private func projectionLabel(_ type: PlaybackCoreDomain.ProjectionType) -> String {
        switch type {
        case .flat: return "Flat"
        case .stereoscopicSBS: return "3D SBS"
        case .stereoscopicOU: return "3D OU"
        case .panorama360: return "360\u{00B0}"
        case .panorama180: return "180\u{00B0}"
        case .fisheye: return "Fisheye"
        }
    }

    private func speedLabel(_ speed: PlaybackCoreDomain.PlaybackSpeed) -> String {
        String(format: "%.2f\u{00D7}", speed.value)
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
    let launcher = PlaybackLaunchCoordinator(
        appModel: appModel,
        windowVideoViewModel: windowVideoViewModel
    )
    let fileBrowsingViewModel = FileBrowsingViewModel(localDataSource: LocalDataSourceAdapter()) {
        request in
        launcher.beginPlayback(request)
    }

    PlayerControlsView()
        .environment(appModel)
        .environment(windowVideoViewModel)
        .environment(fileBrowsingViewModel)
        .environment(launcher)
}
