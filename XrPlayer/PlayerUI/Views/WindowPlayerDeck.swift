import SwiftUI

/// Production window-playback chrome, bound to the live playback engine.
///
/// `WindowPlayerDeckView` hosts the shared `FusedPlayerPanel` (transport row,
/// progress / precision timeline, ⋯ menu, ≡-summoned inline settings, and the
/// ⤢/🧘 panorama / immersive entries) driven by `WindowVideoViewModel` +
/// `AppModel` (ADR-0009). `PlaybackOverlayCard` covers the resume / load-failure
/// states (UC-PLAY-02 / 23).

// MARK: - Bottom ornament: the fused player panel, wired to playback

struct WindowPlayerDeckView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel

    var body: some View {
        FusedPlayerPanel(
            live: live,
            settingsLive: settingsLive,
            onInteraction: register
        )
        .onHover { appModel.setControlsFocused($0) }
        .accessibilityIdentifier("PlayerUI-WindowPlayerDeck")
    }

    /// Resets the auto-hide idle timer on every control interaction and keeps
    /// chrome visible. The 8s idle fade itself is driven by `MainView`.
    private func register() {
        appModel.registerControlsInteraction()
        if appModel.showControls == false {
            withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
        }
    }

    // MARK: - Live binding

    private var live: FusedPlayerPanelLive {
        let position = videoViewModel.playbackPosition
        let duration = position.duration
        let remaining = max(0, duration - position.seconds)
        return FusedPlayerPanelLive(
            isPlaying: videoViewModel.playbackState == .playing,
            showsReplay: videoViewModel.playbackState == .ended,
            progress: duration > 0 ? CGFloat(position.seconds / duration) : 0,
            elapsedLabel: PlaybackTimeFormatter.clock(position.seconds),
            remainingLabel: "-" + PlaybackTimeFormatter.clock(remaining),
            duration: duration,
            framesPerSecond: videoViewModel.displayMediaProfile?.frameRate ?? 0,
            onPlayPause: { self.register(); self.togglePlayPause() },
            onSkipBackward: { self.register(); self.videoViewModel.skip(by: -10) },
            onSkipForward: { self.register(); self.videoViewModel.skip(by: 10) },
            onSeek: { p in
                self.register()
                self.videoViewModel.seek(to: Double(p) * duration)
            },
            onFrameStep: { direction in
                self.register()
                if direction < 0 {
                    self.videoViewModel.frameStepBackward()
                } else {
                    self.videoViewModel.frameStepForward()
                }
            },
            onEnterPanorama: { self.enterPlaybackMode(.panorama) },
            onEnterImmersive: { self.enterPlaybackMode(.immersive) },
            subtitleItems: subtitleItems,
            audioItems: audioItems,
            speedItems: speedItems,
            episodeItems: []
        )
    }

    /// ⤢ 全景 / 🧘 虚拟场景入口:切 playbackMode 触发沉浸空间进出(由 MainView 监听驱动),
    /// 守 inTransition 避免抖动。沿用原 PlaybackSettingsPanel 的 Play Mode 卡语义。
    private func enterPlaybackMode(_ mode: PlaybackMode) {
        register()
        guard mode != appModel.playbackMode,
              appModel.immersiveSpaceState != .inTransition else { return }
        appModel.updatePlaybackMode(mode)
    }

    // MARK: - Settings 桶① 绑定(Display Mode→stereo、180/360→projection)

    private var settingsLive: PlaybackSettingsLive {
        PlaybackSettingsLive(
            displayMode: Binding(
                get: { Self.displayModeLabel(appModel.effectiveStereoLayout) },
                set: { label in
                    register()
                    appModel.setStereoLayoutOverride(Self.stereoLayout(forLabel: label))
                }
            ),
            projection180: projectionBinding(.equirectangular180),
            projection360: projectionBinding(.equirectangular360)
        )
    }

    private func projectionBinding(_ type: PlaybackCoreDomain.ProjectionType) -> Binding<Bool> {
        Binding(
            get: { appModel.effectiveProjectionType == type },
            set: { isOn in
                self.register()
                // 单一 projectionOverride 天然互斥:开则设为该投影,关则回平面。
                self.appModel.setProjectionOverride(isOn ? type : .flat)
            }
        )
    }

    private static func displayModeLabel(_ layout: PlaybackCoreDomain.StereoLayout) -> String {
        switch layout {
        case .mono: "Flat"
        case .sideBySide: "SBS"
        case .topBottom: "TB"
        }
    }

    private static func stereoLayout(forLabel label: String) -> PlaybackCoreDomain.StereoLayout {
        switch label {
        case "SBS": .sideBySide
        case "TB": .topBottom
        default: .mono
        }
    }

    private func togglePlayPause() {
        switch videoViewModel.playbackState {
        case .ended: videoViewModel.replay()
        case .playing: videoViewModel.pause()
        default: videoViewModel.resume()
        }
    }

    private var subtitleItems: [DeckMenuItem] {
        let current = videoViewModel.currentSubtitleTrackID
        var items = videoViewModel.availableSubtitleTracks.map { track in
            DeckMenuItem(id: track.id, title: track.displayName, isSelected: current == track.id) {
                self.register()
                self.videoViewModel.selectSubtitleTrack(track)
            }
        }
        items.append(
            DeckMenuItem(id: "off", title: "Off", isSelected: current == nil) {
                self.register()
                self.videoViewModel.selectSubtitleTrack(nil)
            }
        )
        return items
    }

    private var audioItems: [DeckMenuItem] {
        let current = videoViewModel.currentAudioTrackID
        return videoViewModel.availableAudioTracks.map { track in
            DeckMenuItem(id: track.id, title: track.displayName, isSelected: current == track.id) {
                self.register()
                self.videoViewModel.selectAudioTrack(track)
            }
        }
    }

    private var speedItems: [DeckMenuItem] {
        PlaybackCoreDomain.PlaybackSpeed.allCases.map { speed in
            DeckMenuItem(
                id: String(speed.value),
                title: Self.formatSpeed(speed.value),
                isSelected: appModel.playbackSpeed == speed
            ) {
                self.register()
                self.videoViewModel.setSpeed(speed)
                self.appModel.updatePlaybackSpeed(speed)
            }
        }
    }

    private static func formatSpeed(_ value: Double) -> String {
        if value == value.rounded() {
            return "\(Int(value))×"
        }
        return "\(String(format: "%g", value))×"
    }
}

// MARK: - Resume / load-failure overlay (UC-PLAY-02 / 23)

/// Centered glass card for the pre-play resume prompt and the load-failure
/// panel, built from the shared glass surface + `GlassCapsuleIconLabelButton`.
struct PlaybackOverlayCard: View {
    let systemImage: String
    let title: String
    let message: String
    let primaryTitle: String
    let primaryIcon: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryIcon: String
    let secondaryAction: () -> Void
    let identifierPrefix: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.40))
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: systemImage)
                    .font(DesignTokens.SymbolSize.hero)
                    .foregroundStyle(.white)

                Text(title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                Text(message)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .multilineTextAlignment(.center)

                HStack(spacing: DesignTokens.Spacing.md) {
                    GlassCapsuleIconLabelButton(
                        title: primaryTitle,
                        systemName: primaryIcon,
                        accessibilityLabel: primaryTitle,
                        action: primaryAction,
                        accessibilityIdentifier: "\(identifierPrefix)-primary"
                    )
                    GlassCapsuleIconLabelButton(
                        title: secondaryTitle,
                        systemName: secondaryIcon,
                        accessibilityLabel: secondaryTitle,
                        action: secondaryAction,
                        accessibilityIdentifier: "\(identifierPrefix)-secondary"
                    )
                }
                .padding(.top, DesignTokens.Spacing.sm)
            }
            .padding(DesignTokens.Spacing.xxxl)
            .frame(maxWidth: DesignTokens.ProgressBar.previewWidth)
            .glassBackgroundEffect(in: DesignTokens.ShapeToken.panel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)-panel")
        .accessibilityLabel(title)
    }
}
