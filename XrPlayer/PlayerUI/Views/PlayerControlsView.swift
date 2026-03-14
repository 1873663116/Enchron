import SwiftUI

public struct PlayerControlsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(PlaybackLaunchCoordinator.self) private var launcher

    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0
    @State private var showDetailedTimeline = false
    @State private var pausedForTimeline = false
    @State private var showInfoPanel = false
    @State private var hasAppliedSmokePanelRequest = false

    public init() {}

    public var body: some View {
        VStack(spacing: 24) { // Increased vertical rhythm
            if showDetailedTimeline {
                DetailedTimelineView(
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showDetailedTimeline = false
                            if pausedForTimeline {
                                pausedForTimeline = false
                                videoViewModel.resume()
                            }
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: 10)),
                    removal: .opacity.combined(with: .scale(scale: 0.98))
                ))
            } else {
                sliderSection
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            VStack(spacing: 28) { // More space between controls for clarity
                primaryControlRow
                secondaryControlRow
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(width: showDetailedTimeline ? 860 : 720)
        .glassBackgroundEffect() // Base spatial material
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous)) // Nested glass layering
        .onHover { isHovering in
            appModel.setControlsFocused(isHovering || showInfoPanel || showDetailedTimeline)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    appModel.registerControlsInteraction()
                    if appModel.showControls == false {
                        appModel.showControls = true
                    }
                }
        )
        .onChange(of: showDetailedTimeline) { _, isVisible in
            appModel.setControlsFocused(isVisible || showInfoPanel)
            appModel.registerControlsInteraction()
        }
        .onChange(of: showInfoPanel) { _, isVisible in
            appModel.setControlsFocused(isVisible || showDetailedTimeline)
            appModel.registerControlsInteraction()
        }
        .task(id: appModel.smokePanelRequest) {
            await applySmokePanelRequestIfNeeded()
        }
        .popover(isPresented: $showInfoPanel, attachmentAnchor: .point(.top), arrowEdge: .top) {
            infoPanel
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private var sliderSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(formatTime(isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 60, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { isDraggingSlider ? dragValue : videoViewModel.playbackPosition.seconds },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(videoViewModel.playbackPosition.duration, 1),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            videoViewModel.seek(to: dragValue)
                        }
                    }
                )
                .tint(.white)
                .frame(minHeight: 44)

                Text(formatTime(videoViewModel.playbackPosition.duration))
                    .font(.caption2.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primaryControlRow: some View {
        HStack(spacing: 40) {
            Button {
                videoViewModel.skip(by: -10)
            } label: {
                Image(systemName: "backward.10")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 72, prominence: .primary))
            .help("Backward 10s")

            Button {
                if videoViewModel.playbackState == .ended {
                    videoViewModel.replay()
                } else if videoViewModel.playbackState == .playing {
                    videoViewModel.pause()
                } else {
                    videoViewModel.resume()
                }
            } label: {
                Image(systemName: playButtonIcon)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(
                PlayerControlSurfaceStyle(
                    size: 72,
                    isSelected: videoViewModel.playbackState == .playing,
                    prominence: .primary
                )
            )

            Button {
                videoViewModel.skip(by: 10)
            } label: {
                Image(systemName: "forward.10")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 72, prominence: .primary))
            .help("Forward 10s")
        }
    }

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

    @ViewBuilder
    private var secondaryControlRow: some View {
        HStack(spacing: 24) {
            speedMenu
            tracksMenu
            playlistMenu

            Button {
                appModel.registerControlsInteraction()
                showInfoPanel.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(showInfoPanel ? Color.accentColor : Color.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 60, isSelected: showInfoPanel))
            .help("Media Info")

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if showDetailedTimeline {
                        showDetailedTimeline = false
                        if pausedForTimeline {
                            pausedForTimeline = false
                            videoViewModel.resume()
                        }
                    } else {
                        showInfoPanel = false
                        showDetailedTimeline = true
                        if videoViewModel.playbackState == .playing {
                            pausedForTimeline = true
                            videoViewModel.pause()
                        }
                    }
                }
            } label: {
                Image(systemName: "waveform.path")
                    .font(.title3)
                    .foregroundStyle(showDetailedTimeline ? Color.accentColor : Color.primary)
            }
            .buttonStyle(PlayerControlSurfaceStyle(size: 60, isSelected: showDetailedTimeline))
            .help("Toggle Detailed Timeline")
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.self) { speed in
                Button {
                    videoViewModel.setSpeed(speed)
                    appModel.updatePlaybackSpeed(speed)
                } label: {
                    if appModel.playbackSpeed == speed {
                        Label(speedLabel(speed), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(speed))
                    }
                }
            }
        } label: {
            Text(String(format: "%.1f\u{00D7}", appModel.playbackSpeed.value))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
    }

    private var tracksMenu: some View {
        Menu {
            Section("Audio") {
                ForEach(videoViewModel.availableAudioTracks) { track in
                    Button {
                        videoViewModel.selectAudioTrack(track)
                    } label: {
                        if videoViewModel.currentAudioTrackID == track.id {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
            }

            Section("Subtitles") {
                Button {
                    videoViewModel.selectSubtitleTrack(nil)
                } label: {
                    if videoViewModel.currentSubtitleTrackID == nil || videoViewModel.currentSubtitleTrackID == "no" {
                        Label("Off", systemImage: "checkmark")
                    } else {
                        Text("Off")
                    }
                }

                ForEach(videoViewModel.availableSubtitleTracks) { track in
                    Button {
                        videoViewModel.selectSubtitleTrack(track)
                    } label: {
                        if videoViewModel.currentSubtitleTrackID == track.id {
                            Label(track.displayName, systemImage: "checkmark")
                        } else {
                            Text(track.displayName)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "text.bubble")
                .font(.title3)
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
        .help("Audio and Subtitles")
    }

    private var playlistMenu: some View {
        Menu {
            if fileBrowsingViewModel.files.isEmpty {
                Text("No playlist items")
            } else {
                ForEach(fileBrowsingViewModel.files, id: \.id) { file in
                    Button {
                        Task {
                            do {
                                let request = try await fileBrowsingViewModel.playbackRequest(for: file)
                                await MainActor.run {
                                    launcher.beginPlayback(request)
                                }
                            } catch {
                                await MainActor.run {
                                    fileBrowsingViewModel.lastErrorMessage = "Failed to open \"\(file.name)\": \(error.localizedDescription)"
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
        } label: {
            Image(systemName: "list.bullet")
                .font(.title3)
                .foregroundStyle(.primary)
                .playerControlSurface(size: 60)
        }
        .buttonStyle(.plain)
        .help("Playlist")
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Media Info")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showInfoPanel = false
                }
                .buttonStyle(.plain)
            }

            if let profile = videoViewModel.displayMediaProfile {
                infoRow("HDR", value: hdrTypeLabel(profile.hdrType))
                infoRow(
                    "Output",
                    value: hdrOutputDescription(for: videoViewModel.hdrOutputMode)
                )
                infoRow(
                    "Resolution",
                    value: "\(profile.resolution.width)×\(profile.resolution.height)"
                )
                infoRow("Frame Rate", value: formatFrameRate(profile.frameRate))
            } else {
                Text("Loading media profile…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            infoRow("File Size", value: formatFileSize(videoViewModel.displayFileSizeInBytes))

            if let profile = videoViewModel.displayMediaProfile, profile.hdrType != .sdr {
                Divider()
                Button {
                    videoViewModel.setHDREnabled(videoViewModel.isHDROutputEnabled == false)
                } label: {
                    HStack {
                        Text(videoViewModel.isHDROutputEnabled ? "Switch to SDR" : "Switch to HDR")
                        Spacer()
                        Image(systemName: videoViewModel.isHDROutputEnabled ? "sun.max" : "sparkles.tv")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func infoRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
        }
    }

    @MainActor
    private func applySmokePanelRequestIfNeeded() async {
        guard hasAppliedSmokePanelRequest == false,
              let request = appModel.smokePanelRequest else {
            return
        }

        hasAppliedSmokePanelRequest = true
        appModel.showControls = true
        try? await Task.sleep(for: .seconds(1))

        if request == "timeline" {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                showDetailedTimeline = true
                if videoViewModel.playbackState == .playing {
                    pausedForTimeline = true
                    videoViewModel.pause()
                }
            }
        }
    }

    private func speedLabel(_ speed: PlaybackCoreDomain.PlaybackSpeed) -> String {
        String(format: "%.2f\u{00D7}", speed.value)
    }

    private func formatTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    private func formatFrameRate(_ frameRate: Double) -> String {
        guard frameRate > 0 else {
            return "Unknown"
        }
        return String(format: "%.2f fps", frameRate)
    }

    private func formatFileSize(_ sizeInBytes: Int64?) -> String {
        guard let sizeInBytes, sizeInBytes > 0 else {
            return "Unknown"
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeInBytes)
    }

    private func hdrOutputDescription(for outputMode: PlaybackCoreDomain.HDROutputMode) -> String {
        switch outputMode {
        case .passthroughHDR:
            return "HDR Passthrough"
        case .toneMappedSDR:
            return "Tone-Mapped SDR"
        case .previewSDR:
            return "SDR Preview"
        case .unsupported:
            return "Unavailable"
        }
    }

    private func hdrTypeLabel(_ hdrType: PlaybackCoreDomain.HDRType) -> String {
        switch hdrType {
        case .sdr:
            return "SDR"
        case .hdr10:
            return "HDR10"
        case .hdr10Plus:
            return "HDR10+"
        case .dolbyVision:
            return "Dolby Vision"
        case .hlg:
            return "HLG"
        }
    }
}

#Preview {
    let appModel = AppModel()
    let windowVideoViewModel = WindowVideoViewModel(player: MPVPlayerAdapter())
    let launcher = PlaybackLaunchCoordinator(
        appModel: appModel,
        windowVideoViewModel: windowVideoViewModel
    )
    let fileBrowsingViewModel = FileBrowsingViewModel(localDataSource: LocalDataSourceAdapter()) { request in
        launcher.beginPlayback(request)
    }

    PlayerControlsView()
        .environment(appModel)
        .environment(windowVideoViewModel)
        .environment(fileBrowsingViewModel)
        .environment(launcher)
}
