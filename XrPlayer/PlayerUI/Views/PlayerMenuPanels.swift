import SwiftUI

// MARK: - Design Constants (from player.html)

/// Shared animation parameters matching visionOS system spring.
enum MenuAnimation {
    static let spring: Animation = .spring(duration: 0.35, bounce: 0.15)
}

/// Consistent hover shape for all menu items.
private let itemShape = RoundedRectangle(cornerRadius: DesignTokens.Radius.card - 8, style: .continuous)

/// Button style that suppresses all system-added hover effects.
/// Use this with an explicit `.hoverEffect()` to avoid double-hover on visionOS.
private struct NoSystemHoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

enum MenuSubMenu: Equatable {
    case subtitles
    case audioTrack
    case playbackSpeed
}

enum SettingsSubMenu: Equatable {
    case playbackMode
    case environment
}

// MARK: - Menu Main Panel (Left Button)

/// Main panel content for the left "Menu" button.
/// Each panel has its own glass background — no shared wrapper.
struct MenuPopoverContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Binding var activeSubMenu: MenuSubMenu?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if videoViewModel.isHDRContent {
                hdrToggleRow
            }
            menuRow(label: "Subtitles", isActive: activeSubMenu == .subtitles) {
                toggleSub(.subtitles)
            }
            menuRow(label: "Audio Track", isActive: activeSubMenu == .audioTrack) {
                toggleSub(.audioTrack)
            }
            menuRow(label: "Playback Speed", isActive: activeSubMenu == .playbackSpeed) {
                toggleSub(.playbackSpeed)
            }
        }
        .frame(width: 190)
        .padding(8)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private func toggleSub(_ sub: MenuSubMenu) {
        withAnimation(MenuAnimation.spring) {
            activeSubMenu = activeSubMenu == sub ? nil : sub
        }
    }

    private var hdrToggleRow: some View {
        Button {
            videoViewModel.setHDREnabled(!videoViewModel.isHDROutputEnabled)
        } label: {
            HStack {
                Text(videoViewModel.isHDROutputEnabled ? "ON" : "OFF")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(red: 0.678, green: 0.776, blue: 1.0))
                Spacer()
                Text(hdrLabel)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
        }
        .buttonStyle(NoSystemHoverButtonStyle())
        .clipShape(itemShape)
        .hoverEffect(.highlight)
    }

    private var hdrLabel: String {
        switch videoViewModel.displayMediaProfile?.hdrType {
        case .dolbyVision: return "DV Source"
        case .hdr10: return "HDR10 EDR"
        case .hdr10Plus: return "HDR10+ Source"
        case .hlg: return "HLG"
        default: return "HDR"
        }
    }

    private func menuRow(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.4))
                Spacer()
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(isActive ? .white.opacity(0.08) : .clear, in: itemShape)
        }
        .buttonStyle(NoSystemHoverButtonStyle())
        .clipShape(itemShape)
        .hoverEffect(.highlight)
    }

    // MARK: - Sub-menu (separate view for independent glass panel)

    /// Renders the sub-menu content in its own glass panel.
    /// Used as a sibling in HStack, NOT inside the main panel.
    struct SubMenuOnly: View {
        @Binding var activeSubMenu: MenuSubMenu?
        var videoViewModel: WindowVideoViewModel
        var appModel: AppModel

        @State private var selectedSubtitleID: String?
        @State private var selectedAudioID: String?

        var body: some View {
            Group {
                switch activeSubMenu {
                case .subtitles: subtitlesMenu
                case .audioTrack: audioTrackMenu
                case .playbackSpeed: playbackSpeedMenu
                case .none: EmptyView()
                }
            }
            .padding(8)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .onAppear {
                selectedSubtitleID = videoViewModel.currentSubtitleTrackID
                selectedAudioID = videoViewModel.currentAudioTrackID
            }
        }

        private var subtitlesMenu: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(videoViewModel.availableSubtitleTracks) { track in
                    subItem(label: track.displayName, isSelected: selectedSubtitleID == track.id) {
                        videoViewModel.selectSubtitleTrack(track)
                        selectedSubtitleID = track.id
                    }
                }
                subItem(label: "Off", isSelected: selectedSubtitleID == nil, dimmed: true) {
                    videoViewModel.selectSubtitleTrack(nil)
                    selectedSubtitleID = nil
                }
            }
            .frame(width: 160)
        }

        private var audioTrackMenu: some View {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(videoViewModel.availableAudioTracks) { track in
                    subItem(label: track.displayName, isSelected: selectedAudioID == track.id) {
                        videoViewModel.selectAudioTrack(track)
                        selectedAudioID = track.id
                    }
                }
            }
            .frame(width: 200)
        }

        private var playbackSpeedMenu: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(PlaybackCoreDomain.PlaybackSpeed.allCases, id: \.self) { speed in
                        subItem(
                            label: String(format: "%.2f\u{00D7}", speed.value),
                            isSelected: appModel.playbackSpeed == speed,
                            dimmed: speed.value < 1.0
                        ) {
                            videoViewModel.setSpeed(speed)
                            appModel.updatePlaybackSpeed(speed)
                        }
                    }
                }
            }
            .frame(width: 140)
            .frame(maxHeight: 240)
        }

        private func subItem(
            label: String, isSelected: Bool, dimmed: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                HStack {
                    Text(isSelected ? "\(label) ✓" : label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            isSelected ? Color(red: 0.678, green: 0.776, blue: 1.0)
                                : dimmed ? .primary.opacity(0.5) : .primary
                        )
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 60)
            }
            .buttonStyle(NoSystemHoverButtonStyle())
            .clipShape(itemShape)
            .hoverEffect(.highlight)
        }
    }
}

// MARK: - Settings Main Panel (Right Button)

struct SettingsPopoverContent: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Binding var activeSubMenu: SettingsSubMenu?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuRow(label: "Playback Mode", isActive: activeSubMenu == .playbackMode) {
                toggleSub(.playbackMode)
            }
            if appModel.immersiveSpaceState == .open {
                menuRow(label: "Environment", isActive: activeSubMenu == .environment) {
                    toggleSub(.environment)
                }
            }
        }
        .frame(width: 200)
        .padding(8)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
    }

    private func toggleSub(_ sub: SettingsSubMenu) {
        withAnimation(MenuAnimation.spring) {
            activeSubMenu = activeSubMenu == sub ? nil : sub
        }
    }

    private func menuRow(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(isActive ? .white.opacity(0.08) : .clear, in: itemShape)
        }
        .buttonStyle(NoSystemHoverButtonStyle())
        .clipShape(itemShape)
        .hoverEffect(.highlight)
    }

    // MARK: - Sub-menu (separate glass panel)

    struct SubMenuOnly: View {
        @Binding var activeSubMenu: SettingsSubMenu?
        var appModel: AppModel

        var body: some View {
            Group {
                switch activeSubMenu {
                case .playbackMode: playbackModeMenu
                case .environment: environmentMenu
                case .none: EmptyView()
                }
            }
            .padding(8)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        }

        private var playbackModeMenu: some View {
            let allowed = DecidePlaybackModeUseCase.allowedModes(for: appModel.effectiveProjectionType)
            return VStack(alignment: .leading, spacing: 2) {
                ForEach(PlaybackMode.allCases, id: \.self) { mode in
                    let isSelected = appModel.playbackMode == mode
                    let isDisabled = !allowed.contains(mode) || mode == appModel.playbackMode
                        || appModel.immersiveSpaceState == .inTransition
                    Button {
                        guard mode != appModel.playbackMode, appModel.immersiveSpaceState != .inTransition else { return }
                        appModel.updatePlaybackMode(mode)
                    } label: {
                        HStack {
                            Text(isSelected ? "\(modeLabel(mode)) ✓" : modeLabel(mode))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(
                                    isSelected ? Color(red: 0.678, green: 0.776, blue: 1.0)
                                        : isDisabled ? .primary.opacity(0.5) : .primary
                                )
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 60)
                    }
                    .buttonStyle(NoSystemHoverButtonStyle())
                    .clipShape(itemShape)
                    .hoverEffect(.highlight)
                    .disabled(isDisabled)
                }
            }
            .frame(width: 170)
        }

        private var environmentMenu: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) { env in
                        let isActive = appModel.currentCinemaEnvironment == env
                        Button {
                            Task { await appModel.switchEnvironment(to: env) }
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(environmentGradient(for: env))
                                    .frame(width: 48, height: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(env.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(isActive ? Color(red: 0.678, green: 0.776, blue: 1.0) : .primary)
                                    Text(isActive ? "Active" : environmentCategory(for: env))
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary.opacity(0.4))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 60)
                            .background(isActive ? Color(red: 0.678, green: 0.776, blue: 1.0).opacity(0.08) : .clear)
                        }
                        .buttonStyle(NoSystemHoverButtonStyle())
                        .clipShape(itemShape)
                        .hoverEffect(.highlight)
                    }
                }
            }
            .frame(width: 200)
            .frame(maxHeight: 240)
        }

        private func modeLabel(_ mode: PlaybackMode) -> String {
            switch mode {
            case .window: return "Window"
            case .immersive: return "Immersive"
            case .panorama: return "Panorama"
            }
        }

        private func environmentGradient(for env: SpatialSceneDomain.CinemaEnvironment) -> LinearGradient {
            switch env {
            case .darkTheatre:
                return LinearGradient(colors: [Color(hex: 0x1a1a2e), Color(hex: 0x16213e)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .starryNight:
                return LinearGradient(colors: [Color(hex: 0x312e81), Color(hex: 0x1e1b4b)], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .sunsetNature:
                return LinearGradient(colors: [Color(hex: 0x78350f), Color(hex: 0x451a03)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }

        private func environmentCategory(for env: SpatialSceneDomain.CinemaEnvironment) -> String {
            switch env {
            case .darkTheatre: return "Classic"
            case .starryNight: return "Space"
            case .sunsetNature: return "Nature"
            }
        }
    }
}

// MARK: - Color Hex Helper

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
