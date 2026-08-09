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
        Group {
            if usesWindowPlaybackControls {
                WindowPlaybackControls(
                    live: live,
                    onInteraction: register,
                    controlsVisible: appModel.showControls
                )
                .onHover { appModel.setControlsFocused($0) }
            } else {
                PlayerControlDock(
                    live: live,
                    onInteraction: register,
                    controlsVisible: appModel.showControls
                )
                .onHover { appModel.setControlsFocused($0) }
            }
        }
        .alert(
            "Subtitle Error",
            isPresented: Binding(
                get: { playbackRuntime.subtitleErrorMessage != nil },
                set: { if !$0 { playbackRuntime.subtitleErrorMessage = nil } }
            )
        ) {
            Button("OK") { playbackRuntime.subtitleErrorMessage = nil }
        } message: {
            Text(playbackRuntime.subtitleErrorMessage ?? "The subtitle file could not be loaded.")
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
                && playbackRuntime.effectiveContentIsPanoramic,
            screenScale: appModel.screenScale,
            recommendedScreenScale: EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: appModel.currentCinemaEnvironment.rawValue
            ),
            screenDistance: appModel.screenDepthOffset,
            screenElevationDegrees: appModel.screenViewAngle,
            projection: playbackRuntime.effectiveProjectionType,
            horizontalFieldOfViewDegrees: playbackRuntime.effectiveHorizontalFieldOfViewDegrees,
            stereoLayout: playbackRuntime.effectiveStereoLayout,
            mediaFormatSummary: playbackRuntime.activeMediaFormatProvenance == .source
                ? playbackRuntime.sourceMediaFormatSummary
                : nil,
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
            onExitSpatial: {
                self.enterPlaybackPresentation(
                    self.resolvedPresentation == .panorama ? .portal : .window
                )
            },
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
            subtitleItems: subtitleItems,
            audioItems: audioItems,
            speedItems: speedItems,
            episodeItems: episodeItems
        )
    }

    private var resolvedPresentation: PlaybackPresentation {
        presentationOverride ?? appModel.playbackPresentation
    }

    private var usesWindowPlaybackControls: Bool {
        resolvedPresentation.usesMainWindow
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
        if presentation.usesImmersiveSpace {
            guard playbackRuntime.canEnterSpatialPresentation else { return }
        }
        if presentation == .panorama {
            guard playbackRuntime.effectiveContentIsPanoramic else { return }
        }
        do {
            _ = try appModel.requestPlaybackPresentation(
                presentation,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
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
                Task {
                    do {
                        try await self.playbackLauncher.selectSubtitleTrack(track)
                    } catch {
                        self.playbackRuntime.subtitleErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        items.append(
            DeckMenuItem(id: "off", title: "Off", isSelected: current == nil) {
                self.register()
                Task {
                    do {
                        try await self.playbackLauncher.selectSubtitleTrack(nil)
                    } catch {
                        self.playbackRuntime.subtitleErrorMessage = error.localizedDescription
                    }
                }
            }
        )
        return items
    }

    private var audioItems: [DeckMenuItem] {
        let current = playbackRuntime.currentAudioTrackID
        return playbackRuntime.availableAudioTracks.map { track in
            DeckMenuItem(id: track.id, title: track.displayName, isSelected: current == track.id) {
                self.register()
                Task {
                    do {
                        try await self.playbackLauncher.selectAudioTrack(track)
                    } catch {
                        self.playbackRuntime.lastErrorMessage = error.localizedDescription
                    }
                }
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
                Menu("Subtitles") {
                    selectableMenuItems(subtitleItems)
                }
                .accessibilityIdentifier("PlayerUI-menu-subtitles")
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
        .alert(
            "Subtitle Error",
            isPresented: Binding(
                get: { playbackRuntime.subtitleErrorMessage != nil },
                set: { if !$0 { playbackRuntime.subtitleErrorMessage = nil } }
            )
        ) {
            Button("OK") { playbackRuntime.subtitleErrorMessage = nil }
        } message: {
            Text(playbackRuntime.subtitleErrorMessage ?? "The subtitle file could not be loaded.")
        }
    }

    @ViewBuilder
    private func menuSection(_ title: String, items: [DeckMenuItem]) -> some View {
        Menu(title) {
            selectableMenuItems(items)
        }
    }

    @ViewBuilder
    private func selectableMenuItems(_ items: [DeckMenuItem]) -> some View {
        Picker("", selection: selection(items)) {
            ForEach(items) { item in
                Text(item.title)
                    .tag(item.id)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
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
                Task {
                    do {
                        try await playbackLauncher.selectSubtitleTrack(track)
                    } catch {
                        playbackRuntime.subtitleErrorMessage = error.localizedDescription
                    }
                }
            }
        }
        items.append(
            DeckMenuItem(id: "off", title: "Off", isSelected: current == nil) {
                register()
                Task {
                    do {
                        try await playbackLauncher.selectSubtitleTrack(nil)
                    } catch {
                        playbackRuntime.subtitleErrorMessage = error.localizedDescription
                    }
                }
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
                Task {
                    do {
                        try await playbackLauncher.selectAudioTrack(track)
                    } catch {
                        playbackRuntime.lastErrorMessage = error.localizedDescription
                    }
                }
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

// MARK: - Resume decision (UC-PLAY-02)

/// The pre-play decision remains part of the media-opening flow. Playback
/// failures use a system alert instead of sharing this product-owned surface.
struct ResumeDecisionCard: View {
    let message: String
    let onResume: () -> Void
    let onStartOver: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.40))
                .ignoresSafeArea()

            VStack(spacing: DesignTokens.Spacing.lg) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignTokens.SymbolSize.hero)
                    .foregroundStyle(.white)

                Text("Resume Playback?")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                Text(message)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
                    .multilineTextAlignment(.center)

                HStack(spacing: DesignTokens.Spacing.md) {
                    GlassCapsuleIconLabelButton(
                        title: "Resume",
                        systemName: "play.fill",
                        accessibilityLabel: "Resume",
                        action: onResume,
                        accessibilityIdentifier: "PlayerUI-resumeDecision-primary"
                    )
                    GlassCapsuleIconLabelButton(
                        title: "Start Over",
                        systemName: "backward.end.fill",
                        accessibilityLabel: "Start Over",
                        action: onStartOver,
                        accessibilityIdentifier: "PlayerUI-resumeDecision-secondary"
                    )
                }
                .padding(.top, DesignTokens.Spacing.sm)
            }
            .padding(DesignTokens.Spacing.xxxl)
            .frame(maxWidth: DesignTokens.ProgressBar.previewWidth)
            .glassBackgroundEffect(in: DesignTokens.ShapeToken.panel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-resumeDecision-panel")
        .accessibilityLabel("Resume Playback?")
    }
}
