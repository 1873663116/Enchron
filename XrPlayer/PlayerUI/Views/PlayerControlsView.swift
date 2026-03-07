import SwiftUI

public struct PlayerControlsView: View {
    private enum AuxiliaryPanel {
        case tracks
        case playlist
    }

    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel

    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0
    @State private var activePanel: AuxiliaryPanel?
    @State private var showDetailedTimeline = false
    @State private var pausedForTimeline = false
    @State private var hasAppliedSmokePanelRequest = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            // HDR Badge + Toggle
            HStack(spacing: 12) {
                if let hdrType = videoViewModel.currentMediaProfile?.hdrType, hdrType != .sdr {
                    Text(hdrType.rawValue.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.3)))

                    Button {
                        videoViewModel.setHDREnabled(!videoViewModel.isHDROutputEnabled)
                    } label: {
                        Text(videoViewModel.isHDROutputEnabled ? "HDR" : "SDR")
                            .font(.caption.bold())
                            .foregroundStyle(videoViewModel.isHDROutputEnabled ? .orange : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().stroke(
                                    videoViewModel.isHDROutputEnabled ? Color.orange : Color.secondary,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Main Slider Area
            if showDetailedTimeline {
                DetailedTimelineView(
                    onClose: {
                        withAnimation(.spring()) {
                            showDetailedTimeline = false
                            if pausedForTimeline {
                                pausedForTimeline = false
                                videoViewModel.resume()
                            }
                        }
                    }
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                sliderSection
            }

            if activePanel != nil {
                floatingPanelHost
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 20) {
                primaryControlRow
                secondaryControlRow
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: controlsWidth)
        .glassBackgroundEffect()
        .task(id: appModel.smokePanelRequest) {
            await applySmokePanelRequestIfNeeded()
        }
    }

    private var controlsWidth: CGFloat {
        if showDetailedTimeline {
            return 860
        }
        if activePanel != nil {
            return 760
        }
        return 720
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
                Image(systemName: "backward.10.fill")
                    .font(.title)
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
                    .font(.system(size: 44))
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                videoViewModel.skip(by: 10)
            } label: {
                Image(systemName: "forward.10.fill")
                    .font(.title)
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
        HStack(spacing: 32) {
            Menu {
                ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.self) { speed in
                    Button {
                        videoViewModel.setSpeed(speed)
                        appModel.updatePlaybackSpeed(speed)
                    } label: {
                        HStack {
                            Text(String(format: "%.2f\u{00D7}", speed.value))
                            if appModel.playbackSpeed == speed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.1f\u{00D7}", appModel.playbackSpeed.value))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 60, height: 60)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            panelToggleButton(
                systemImage: "text.bubble",
                panel: .tracks,
                helpText: "Audio and Subtitles"
            )

            panelToggleButton(
                systemImage: "list.bullet",
                panel: .playlist,
                helpText: "Playlist"
            )

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    activePanel = nil
                    if showDetailedTimeline {
                        showDetailedTimeline = false
                        if pausedForTimeline {
                            pausedForTimeline = false
                            videoViewModel.resume()
                        }
                    } else {
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
                    .foregroundStyle(showDetailedTimeline ? .orange : .white)
                    .frame(width: 60, height: 60)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Toggle Detailed Timeline")
        }
    }

    @ViewBuilder
    private var floatingPanelHost: some View {
        ZStack {
            PlaybackMenuView(onClose: closeAuxiliaryPanel)
                .opacity(activePanel == .tracks ? 1 : 0.001)
                .allowsHitTesting(activePanel == .tracks)
                .accessibilityHidden(activePanel != .tracks)

            PlaylistView(onClose: closeAuxiliaryPanel)
                .opacity(activePanel == .playlist ? 1 : 0.001)
                .allowsHitTesting(activePanel == .playlist)
                .accessibilityHidden(activePanel != .playlist)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: activePanel == nil)
    }

    @ViewBuilder
    private func panelToggleButton(systemImage: String, panel: AuxiliaryPanel, helpText: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                showDetailedTimeline = false
                activePanel = activePanel == panel ? nil : panel
            }
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(activePanel == panel ? .orange : .white)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func closeAuxiliaryPanel() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            activePanel = nil
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

        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            switch request {
            case "tracks":
                activePanel = .tracks
            case "timeline":
                showDetailedTimeline = true
                if videoViewModel.playbackState == .playing {
                    pausedForTimeline = true
                    videoViewModel.pause()
                }
            default:
                break
            }
        }
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
}

#Preview {
    PlayerControlsView()
        .environment(AppModel())
        .environment(WindowVideoViewModel(player: MPVPlayerAdapter()))
}
