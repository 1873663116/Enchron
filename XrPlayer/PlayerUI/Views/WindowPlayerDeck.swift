import SwiftUI

/// Production window-playback chrome, assembled entirely from the polished
/// component library and bound to the live playback engine.
///
/// `WindowPlayerDeckView` hosts the shared `PlayerControlDeck` (transport row,
/// progress / precision timeline, ⋯ menu) driven by `WindowVideoViewModel`.
/// `PlaybackSettingsPanel` is the leading ornament, composed from the shared
/// `CategorySidebar` + `SettingListGroup`. `PlaybackOverlayCard` covers the
/// resume / load-failure states (UC-PLAY-02 / 23).
///
/// This retires the bespoke `PlayerControlsView` / `SeekBarView` /
/// `NLETimelineView` / `MenuPopoverContent` / `SettingsPopoverContent`: the
/// player surface the user sees is now the polished deck, not a one-off.

// MARK: - Bottom ornament: the polished deck, wired to playback

struct WindowPlayerDeckView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel

    var body: some View {
        PlayerControlDeck(
            onOpenSettings: openSettingsPanel,
            live: live
        )
        .onHover { appModel.setControlsFocused($0) }
        .accessibilityIdentifier("PlayerUI-WindowPlayerDeck")
    }

    private func openSettingsPanel() {
        register()
        withAnimation(DesignTokens.AnimationToken.panelSpring) {
            appModel.showPlayerSettingsPopup.toggle()
        }
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

    private var live: PlayerControlDeckLive {
        let position = videoViewModel.playbackPosition
        let duration = position.duration
        let remaining = max(0, duration - position.seconds)
        return PlayerControlDeckLive(
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
            subtitleItems: subtitleItems,
            audioItems: audioItems,
            speedItems: speedItems,
            episodeItems: []
        )
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

// MARK: - Leading ornament: polished playback settings panel

/// Playback settings, composed from the shared `CategorySidebar` +
/// `SettingListGroup`. Replaces the retired `SettingsPopoverContent`.
/// Play Mode + Environment are bound to live `AppModel` state; the libplacebo
/// Picture parameters are presented read-only until a real mpv backend lands.
struct PlaybackSettingsPanel: View {
    @Environment(AppModel.self) private var appModel

    @State private var selectedCategoryID = Category.environment.rawValue

    private enum Category: String, CaseIterable {
        case environment, playMode, picture

        var title: String {
            switch self {
            case .environment: "Environment"
            case .playMode: "Play Mode"
            case .picture: "Picture"
            }
        }

        var icon: String {
            switch self {
            case .environment: "mountain.2.fill"
            case .playMode: "cube.fill"
            case .picture: "camera.filters"
            }
        }
    }

    private var selectedCategory: Category {
        Category(rawValue: selectedCategoryID) ?? .environment
    }

    var body: some View {
        HStack(spacing: 0) {
            CategorySidebar(
                items: Category.allCases.map { CategorySidebarItem(id: $0.rawValue, icon: $0.icon, title: $0.title) },
                selection: $selectedCategoryID,
                title: "Player",
                width: 196,
                containerIdentifier: "Playback-Settings-sidebar",
                identifierPrefix: "Playback-Settings"
            )

            ScrollView {
                sections(for: selectedCategory)
                    .padding(DesignTokens.Spacing.lg)
                    .id(selectedCategoryID)
                    .transition(.opacity)
            }
            .scrollIndicators(.hidden)
            .frame(width: 360)
            .animation(DesignTokens.AnimationToken.fadeIn, value: selectedCategoryID)
        }
        .frame(maxHeight: 460)
        .glassBackgroundEffect(in: DesignTokens.ShapeToken.panel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Playback-Settings-panel")
    }

    @ViewBuilder
    private func sections(for category: Category) -> some View {
        switch category {
        case .environment:
            SettingListGroup(accessibilityIdentifier: "Playback-Settings-environment-group", items: environmentItems)
        case .playMode:
            SettingListGroup(accessibilityIdentifier: "Playback-Settings-playMode-group", items: playModeItems)
        case .picture:
            SettingListGroup(accessibilityIdentifier: "Playback-Settings-picture-group", items: pictureItems)
        }
    }

    // MARK: - Environment (PLAY-26 / SET-07 vocabulary)

    private var environmentItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "environment-select",
                title: "Environment",
                systemName: "mountain.2",
                accessory: .none,
                embeddedControl: .cardSelection(
                    options: SpatialSceneDomain.CinemaEnvironment.allCases.map {
                        SettingListGroup.CardOption(id: environmentID($0), title: $0.displayName, systemName: "photo")
                    },
                    selectedID: Binding(
                        get: { environmentID(appModel.currentCinemaEnvironment) },
                        set: { id in
                            guard let env = environment(forID: id) else { return }
                            Task { await appModel.switchEnvironment(to: env) }
                        }
                    )
                )
            ),
            SettingListGroup.Item(
                id: "screen-curvature",
                title: "Curved Screen",
                systemName: "tv",
                accessory: .boundToggle(
                    isOn: Binding(
                        get: {
                            if case .curved = appModel.screenShape { return true }
                            return false
                        },
                        set: { curved in
                            appModel.screenShape = curved
                                ? .curved(radius: 3.0, height: 1.35)
                                : .flat(width: 2.4, height: 1.35)
                        }
                    ),
                    isEnabled: true,
                    marker: nil
                )
            )
        ]
    }

    private func environmentID(_ env: SpatialSceneDomain.CinemaEnvironment) -> String {
        switch env {
        case .darkTheatre: "dark"
        case .starryNight: "starry"
        case .sunsetNature: "sunset"
        }
    }

    private func environment(forID id: String) -> SpatialSceneDomain.CinemaEnvironment? {
        switch id {
        case "dark": .darkTheatre
        case "starry": .starryNight
        case "sunset": .sunsetNature
        default: nil
        }
    }

    // MARK: - Play Mode (PLAY-27)

    private var playModeItems: [SettingListGroup.Item] {
        [
            SettingListGroup.Item(
                id: "play-mode-select",
                title: "Play Mode",
                systemName: "cube",
                accessory: .none,
                embeddedControl: .cardSelection(
                    options: [
                        SettingListGroup.CardOption(id: "window", title: "Window", systemName: "macwindow"),
                        SettingListGroup.CardOption(id: "immersive", title: "Immersive", systemName: "visionpro"),
                        SettingListGroup.CardOption(id: "panorama", title: "Panorama", systemName: "pano")
                    ],
                    selectedID: Binding(
                        get: { modeID(appModel.playbackMode) },
                        set: { id in
                            guard let mode = mode(forID: id), mode != appModel.playbackMode,
                                  appModel.immersiveSpaceState != .inTransition else { return }
                            appModel.updatePlaybackMode(mode)
                        }
                    )
                )
            )
        ]
    }

    private func modeID(_ mode: PlaybackMode) -> String {
        switch mode {
        case .window: "window"
        case .immersive: "immersive"
        case .panorama: "panorama"
        }
    }

    private func mode(forID id: String) -> PlaybackMode? {
        switch id {
        case "window": .window
        case "immersive": .immersive
        case "panorama": .panorama
        default: nil
        }
    }

    // MARK: - Picture (PLAY-28 — read-only until real mpv backend)

    private var pictureItems: [SettingListGroup.Item] {
        [
            // EXPLORATORY: libplacebo parameters have no fake backing; presented
            // read-only (pixel response awaits the real mpv adapter). Remove the
            // read-only treatment when the engine swap lands.
            SettingListGroup.Item(
                id: "picture-tone-mapping",
                title: "Tone Mapping",
                systemName: "circle.lefthalf.filled",
                accessory: .value("BT.2390")
            ),
            SettingListGroup.Item(
                id: "picture-peak-detect",
                title: "Peak Detection",
                systemName: "sparkles",
                accessory: .value("Auto")
            ),
            SettingListGroup.Item(
                id: "picture-target-gamut",
                title: "Output Gamut",
                systemName: "paintpalette",
                accessory: .value("Display P3")
            )
        ]
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
