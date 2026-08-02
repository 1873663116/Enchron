import DesignSystem
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

struct WindowPlayerDeckView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    var presentationOverride: PlaybackPresentation? = nil
    var onExitPlayback: (() -> Void)? = nil

    @ViewBuilder
    var body: some View {
        if resolvedPresentation == .window {
            WindowPlaybackControls(
                live: live,
                onInteraction: register
            )
            .onHover { appModel.setControlsFocused($0) }
        } else {
            PlayerControlDock(
                live: live,
                onInteraction: register
            )
            .onHover { appModel.setControlsFocused($0) }
        }
    }

    private func register() {
        appModel.registerControlsInteraction()
        if appModel.showControls == false {
            withAnimation(.easeInOut(duration: 0.4)) { appModel.showControls = true }
        }
    }

    private var live: FusedPlayerPanelLive {
        let position = playbackRuntime.playbackPosition
        let duration = position.duration
        let transport = PlaybackTransportAvailability(
            lifecycle: playbackRuntime.productLifecycle
        )
        return FusedPlayerPanelLive(
            presentation: resolvedPresentation,
            mediaName: mediaName,
            mediaProfile: playbackRuntime.displayMediaProfile,
            canDock: playbackRuntime.canEnterSpatialPresentation,
            canEnterPanorama: playbackRuntime.canEnterSpatialPresentation
                && playbackRuntime.effectiveProjectionType.isPanoramic,
            screenScale: appModel.screenScale,
            recommendedScreenScale: EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: appModel.currentCinemaEnvironment.rawValue
            ),
            screenDistance: appModel.screenDepthOffset,
            screenElevationDegrees: appModel.screenViewAngle,
            projection: playbackRuntime.effectiveProjectionType,
            stereoLayout: playbackRuntime.effectiveStereoLayout,
            canUseFisheye: playbackRuntime.supportsFisheyePresentation,
            isPlaying: transport.primaryAction == .pause,
            showsReplay: transport.primaryAction == .replay,
            canSkipForward: transport.canSkipForward,
            canStepForward: transport.canStepForward,
            progress: duration > 0 ? CGFloat(position.seconds / duration) : 0,
            elapsedLabel: PlaybackTimeFormatter.clock(position.seconds),
            durationLabel: PlaybackTimeFormatter.clock(duration),
            duration: duration,
            framesPerSecond: playbackRuntime.displayMediaProfile?.frameRate ?? 0,
            onPlayPause: { self.register(); self.togglePlayPause() },
            onSkipBackward: { self.register(); self.playbackRuntime.skip(by: -15) },
            onSkipForward: { self.register(); self.playbackRuntime.skip(by: 15) },
            onSeek: { p in
                self.register()
                self.playbackRuntime.seek(
                    to: Double(p) * duration,
                    event: .progressBar
                )
            },
            onPrecisionSeek: { p in
                self.register()
                self.playbackRuntime.seek(
                    to: Double(p) * duration,
                    event: .precisionTimeline
                )
            },
            onFrameStep: { direction in
                self.register()
                if direction < 0 {
                    self.playbackRuntime.frameStepBackward()
                } else {
                    self.playbackRuntime.frameStepForward()
                }
            },
            onEnterPanorama: { self.enterPlaybackPresentation(.panorama) },
            onEnterImmersive: { self.enterPlaybackPresentation(.docked) },
            onExitSpatial: { self.enterPlaybackPresentation(.window) },
            onExitPlayback: {
                if let onExitPlayback = self.onExitPlayback {
                    onExitPlayback()
                } else {
                    self.playbackLauncher.stopPlayback()
                }
            },
            onSetScreenScale: { scale in
                self.register()
                self.appModel.setScreenScale(scale)
            },
            onSetScreenDistance: { distance in
                self.register()
                self.appModel.setScreenDistance(distance)
            },
            onSetScreenElevation: { elevation in
                self.register()
                self.appModel.setScreenElevation(elevation)
            },
            onResetDockedPlacement: {
                self.register()
                self.appModel.resetDockedPlacement()
            },
            onApplyFormat: { projection, stereo in
                self.register()
                Task {
                    do {
                        try await self.playbackLauncher.applyFormat(projection: projection, stereo: stereo)
                    } catch {
                        self.playbackRuntime.lastErrorMessage = error.localizedDescription
                    }
                }
            },
            onResetFormat: {
                self.register()
                Task {
                    do {
                        try await self.playbackLauncher.resetFormat()
                        self.enterPlaybackPresentation(.window)
                    } catch {
                        self.playbackRuntime.lastErrorMessage = error.localizedDescription
                    }
                }
            },
            subtitleItems: subtitleItems,
            audioItems: audioItems,
            speedItems: speedItems,
            episodeItems: episodeItems
        )
    }

    private var resolvedPresentation: PlaybackPresentation {
        presentationOverride ?? appModel.playbackPresentation
    }

    private var mediaName: String {
        guard let url = playbackRuntime.currentPlaybackURL else { return "Unknown" }
        let name = url.deletingPathExtension().lastPathComponent
        return name.removingPercentEncoding ?? name
    }

    private func enterPlaybackPresentation(_ presentation: PlaybackPresentation) {
        register()
        guard presentation != appModel.playbackPresentation,
              appModel.pendingSpatialPlatformEffect == nil else { return }
        if presentation != .window {
            guard playbackRuntime.canEnterSpatialPresentation else { return }
        }
        if presentation == .panorama {
            guard playbackRuntime.effectiveProjectionType.isPanoramic else { return }
        }
        _ = try? appModel.requestPlaybackPresentation(
            presentation,
            mediaSessionID: playbackRuntime.activeSessionID,
            wasPlaying: playbackRuntime.productLifecycle == .playing
        )
    }

    private func togglePlayPause() {
        PlaybackTrace.event("ui.playPause.request lifecycle=\(playbackRuntime.lifecycle.label)")
        switch PlaybackTransportAvailability(
            lifecycle: playbackRuntime.productLifecycle
        ).primaryAction {
        case .replay: playbackRuntime.replay()
        case .pause: playbackRuntime.pause()
        case .play: playbackRuntime.resume()
        }
    }

    private var subtitleItems: [DeckMenuItem] {
        let current = playbackRuntime.currentSubtitleTrackID
        var items = playbackRuntime.availableSubtitleTracks.map { track in
            DeckMenuItem(id: track.id, title: track.displayName, isSelected: current == track.id) {
                self.register()
                self.playbackRuntime.selectSubtitleTrack(track)
            }
        }
        items.append(
            DeckMenuItem(id: "off", title: "Off", isSelected: current == nil) {
                self.register()
                self.playbackRuntime.selectSubtitleTrack(nil)
            }
        )
        return items
    }

    private var audioItems: [DeckMenuItem] {
        let current = playbackRuntime.currentAudioTrackID
        return playbackRuntime.availableAudioTracks.map { track in
            DeckMenuItem(id: track.id, title: track.displayName, isSelected: current == track.id) {
                self.register()
                self.playbackRuntime.selectAudioTrack(track)
            }
        }
    }

    private var speedItems: [DeckMenuItem] {
        PlaybackModel.PlaybackSpeed.allCases.map { speed in
            DeckMenuItem(
                id: String(speed.value),
                title: Self.formatSpeed(speed.value),
                isSelected: playbackRuntime.currentPlaybackSpeed == speed
            ) {
                self.register()
                self.playbackRuntime.setSpeed(speed)
            }
        }
    }

    private var episodeItems: [DeckMenuItem] {
        playbackLauncher.playbackQueue.entries.map { entry in
            DeckMenuItem(
                id: entry.id.uuidString,
                title: entry.displayName,
                isSelected: entry.isCurrent
            ) {
                self.register()
                self.playbackLauncher.selectPlaybackQueueItem(entry.id)
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

/// Production More menu shared by the window chrome. Its label uses the
/// DesignSystem circle control while the menu contents remain feature-owned.
struct ProductionPlaybackMoreMenu: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher

    var body: some View {
        GlassCircleIconMenu(
            systemName: "ellipsis",
            accessibilityLabel: "More",
            accessibilityIdentifier: "PlayerUI-TopAction-more"
        ) {
            if !subtitleItems.isEmpty {
                menuSection("Subtitles", items: subtitleItems)
            }
            if !audioItems.isEmpty {
                menuSection("Audio Track", items: audioItems)
            }
            menuSection("Playback Speed", items: speedItems)
            if !episodeItems.isEmpty {
                menuSection("Episodes", items: episodeItems)
            }
        }
        .accessibilityLabel("More playback settings")
    }

    @ViewBuilder
    private func menuSection(_ title: String, items: [DeckMenuItem]) -> some View {
        Menu(title) {
            Picker("", selection: selection(items)) {
                ForEach(items) { item in
                    Text(item.title)
                        .tag(item.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private func selection(_ items: [DeckMenuItem]) -> Binding<String> {
        Binding(
            get: { items.first(where: \.isSelected)?.id ?? "" },
            set: { id in items.first(where: { $0.id == id })?.action() }
        )
    }

    private func register() {
        appModel.registerControlsInteraction()
    }

    private var subtitleItems: [DeckMenuItem] {
        let current = playbackRuntime.currentSubtitleTrackID
        var items = playbackRuntime.availableSubtitleTracks.map { track in
            DeckMenuItem(
                id: track.id,
                title: track.displayName,
                isSelected: current == track.id
            ) {
                register()
                playbackRuntime.selectSubtitleTrack(track)
            }
        }
        items.append(
            DeckMenuItem(id: "off", title: "Off", isSelected: current == nil) {
                register()
                playbackRuntime.selectSubtitleTrack(nil)
            }
        )
        return items
    }

    private var audioItems: [DeckMenuItem] {
        let current = playbackRuntime.currentAudioTrackID
        return playbackRuntime.availableAudioTracks.map { track in
            DeckMenuItem(
                id: track.id,
                title: track.displayName,
                isSelected: current == track.id
            ) {
                register()
                playbackRuntime.selectAudioTrack(track)
            }
        }
    }

    private var speedItems: [DeckMenuItem] {
        PlaybackModel.PlaybackSpeed.allCases.map { speed in
            DeckMenuItem(
                id: String(speed.value),
                title: Self.formatSpeed(speed.value),
                isSelected: playbackRuntime.currentPlaybackSpeed == speed
            ) {
                register()
                playbackRuntime.setSpeed(speed)
            }
        }
    }

    private var episodeItems: [DeckMenuItem] {
        playbackLauncher.playbackQueue.entries.map { entry in
            DeckMenuItem(
                id: entry.id.uuidString,
                title: entry.displayName,
                isSelected: entry.isCurrent
            ) {
                register()
                playbackLauncher.selectPlaybackQueueItem(entry.id)
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
