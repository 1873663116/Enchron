import SwiftUI

public struct PlayerControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(PlaybackLaunchCoordinator.self) private var launcher
    @Environment(\.openWindow) private var openWindow

    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0
    @State private var showScreenPositionSheet = false
    @State private var showDebugSheet = false
    @State private var lastInteractionTime = Date()
    @State private var hasAppliedSmokePanelRequest = false
    @State private var isTimelineExpanded = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                PlayerInfoBarView()

                sliderSection

                controlRow
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(width: DesignTokens.Layout.playerControlsWidth)
            .enchronGlassControl()

            NLETimelineView(
                isExpanded: $isTimelineExpanded,
                currentTime: videoViewModel.playbackPosition.seconds,
                duration: videoViewModel.playbackPosition.duration,
                onSeek: { videoViewModel.seek(to: $0) },
                onFrameStepForward: { videoViewModel.frameStepForward() },
                onFrameStepBackward: { videoViewModel.frameStepBackward() }
            )
        }
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
                try await Task.sleep(for: .seconds(5))
                guard !appModel.isControlsFocused else { return }
                withAnimation {
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

    // MARK: - Seek Bar

    @ViewBuilder
    private var sliderSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Text(
                    PlaybackTimeFormatter.clock(
                        isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds)
                )
                .font(.caption2.monospacedDigit())
                .frame(width: 60, alignment: .leading)

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
                            registerInteraction()
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

                Text(PlaybackTimeFormatter.clock(videoViewModel.playbackPosition.duration))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }

            // Precision time label and detailed timeline during drag
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

                DetailedTimelineView(
                    duration: videoViewModel.playbackPosition.duration,
                    currentTime: videoViewModel.playbackPosition.seconds,
                    isDragging: isDraggingSlider,
                    dragTime: dragValue
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDraggingSlider)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Control Row

    @ViewBuilder
    private var controlRow: some View {
        HStack(spacing: 28) {
            leftMenu

            Button {
                videoViewModel.skip(by: -10)
                registerInteraction()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.automatic)
            .frame(minWidth: 60, minHeight: 60)
            .contentShape(.rect)
            .help("Backward 10s")
            .accessibilityLabel("Skip backward 10 seconds")

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
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.automatic)
            .frame(minWidth: 72, minHeight: 72)
            .contentShape(.rect)
            .accessibilityLabel(playButtonAccessibilityLabel)

            Button {
                videoViewModel.skip(by: 10)
                registerInteraction()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.automatic)
            .frame(minWidth: 60, minHeight: 60)
            .contentShape(.rect)
            .help("Forward 10s")
            .accessibilityLabel("Skip forward 10 seconds")

            NLETimelineToggleButton(isExpanded: $isTimelineExpanded)

            rightMenu
        }
    }

    // MARK: - Left Menu (Playback Options)

    private var leftMenu: some View {
        Menu {
            // Speed
            Section("Speed") {
                Picker("Speed", selection: speedBinding) {
                    ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.self) { speed in
                        Text(speedLabel(speed)).tag(speed)
                    }
                }
            }

            // HDR toggle (only if content is HDR)
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
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(minWidth: 60, minHeight: 60)
                .contentShape(.rect)
        }
        .buttonStyle(.automatic)
        .help("Playback Options")
        .accessibilityLabel("Playback Options")
    }

    // MARK: - Right Menu (Settings)

    private var rightMenu: some View {
        Menu {
            // Playback mode
            Section("Mode") {
                ForEach(PlaybackMode.allCases, id: \.self) { mode in
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

            // Frame stepping
            Button {
                videoViewModel.frameStepBackward()
            } label: {
                Label("Frame Step Back", systemImage: "backward.frame.fill")
            }
            Button {
                videoViewModel.frameStepForward()
            } label: {
                Label("Frame Step Forward", systemImage: "forward.frame.fill")
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
                .foregroundStyle(.primary)
                .frame(minWidth: 60, minHeight: 60)
                .contentShape(.rect)
        }
        .buttonStyle(.automatic)
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

    /// Requests a playback mode change.
    /// Immersive space transitions and panorama bridge lifecycle are handled
    /// centrally by MainView's onChange(of: playbackMode), keeping this window
    /// decoupled from PanoramaLayerBridge and immersive space APIs.
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
            appModel.showControls = true
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
