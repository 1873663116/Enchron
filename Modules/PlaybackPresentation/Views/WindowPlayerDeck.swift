import DesignSystem
import OSLog
import PlaybackCore
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

struct WindowPlayerDeckView: View {
    private let logger = Logger(subsystem: "app.enchron", category: "PlayerDeck")
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
        .playbackIssueAlert(
            at: .playerDeck,
            onRetry: playbackLauncher.retryPlayback,
            onClose: onExitPlayback ?? playbackLauncher.stopPlayback
        )
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
            canApplyFormat: playbackRuntime.canEnterSpatialPresentation,
            screenScale: appModel.screenScale,
            recommendedScreenScale: EnvironmentSceneMapping.defaultScreenScale(
                forEnvironmentID: appModel.currentCinemaEnvironment.rawValue
            ),
            screenDistance: appModel.screenDepthOffset,
            screenElevationDegrees: appModel.screenViewAngle,
            projection: playbackRuntime.effectiveProjectionType,
            horizontalFieldOfViewDegrees: playbackRuntime.effectiveHorizontalFieldOfViewDegrees,
            stereoLayout: playbackRuntime.effectiveStereoLayout,
            usesDolbyVisionFallback: playbackRuntime.dolbyVisionFallbackIsEnabled,
            showsDolbyVisionFallback: playbackRuntime.dolbyVisionFallbackIsAvailable,
            mediaFormatSummary: playbackRuntime.activeMediaFormatProvenance == .source
                ? playbackRuntime.sourceMediaFormatSummary
                : nil,
            overview: playbackRuntime.overview,
            unmetCapabilities: playbackRuntime.unmetCapabilities,
            mediaFormatProvenance: playbackRuntime.activeMediaFormatProvenance,
            sourceMediaFormatSummary: playbackRuntime.sourceMediaFormatSummary,
            isPlaying: transport.primaryAction == .pause,
            showsReplay: transport.primaryAction == .replay,
            canSkipForward: transport.canSkipForward,
            canStepForward: transport.canStepForward,
            progress: duration > 0 ? CGFloat(position.seconds / duration) : 0,
            elapsedLabel: PlaybackTimeFormatter.clock(position.seconds),
            durationLabel: PlaybackTimeFormatter.clock(duration),
            duration: duration,
            framesPerSecond: playbackRuntime.displayMediaProfile?.frameRate ?? 0,
            onPlayPause: {
                self.register()
#if DEBUG
                self.appModel.recordSurfaceInputProbe(
                    "playback control delivered action=playPause"
                )
#endif
                self.togglePlayPause()
            },
            onSkipBackward: {
                self.register()
#if DEBUG
                self.appModel.recordSurfaceInputProbe(
                    "playback control delivered action=rewind"
                )
#endif
                self.playbackRuntime.skip(by: -15)
            },
            onSkipForward: {
                self.register()
#if DEBUG
                self.appModel.recordSurfaceInputProbe(
                    "playback control delivered action=forward"
                )
#endif
                self.playbackRuntime.skip(by: 15)
            },
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
            onEnterImmersive: { self.enterImmersive() },
            onExitSpatial: { self.exitImmersive() },
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
            onApplyFormat: { projection, horizontalFieldOfViewDegrees, stereo, fallback in
                self.applyFormat(
                    projection,
                    horizontalFieldOfViewDegrees,
                    stereo,
                    fallback
                )
            },
            onRestoreAutomaticFormat: {
                self.restoreAutomaticFormat()
            },
            onReachabilityAction: { action in
#if DEBUG
                self.appModel.recordSurfaceInputProbe(
                    "reachability playerPanel delivered action=\(action)"
                )
#endif
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
        do {
            _ = try appModel.requestPlaybackPresentation(
                presentation,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            logger.error(
                "presentation request failed error=\(error.localizedDescription, privacy: .public)"
            )
            playbackRuntime.setUserVisibleIssue(.presentationTransitionFailed)
        }
    }

    private func enterImmersive() {
        guard let target = appModel.playbackPresentation.enterImmersiveTarget else { return }
        enterPlaybackPresentation(target)
    }

    private func exitImmersive() {
        guard let target = appModel.playbackPresentation.exitImmersiveTarget else { return }
        enterPlaybackPresentation(target)
    }

    private func applyFormat(
        _ projection: PlaybackModel.ProjectionType,
        _ horizontalFieldOfViewDegrees: Int?,
        _ stereo: PlaybackModel.StereoLayout,
        _ usesDolbyVisionFallback: Bool
    ) {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        register()
        Task {
            do {
                try await playbackLauncher.applyFormat(
                    projection: projection,
                    horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
                    stereo: stereo,
                    usesDolbyVisionFallback: usesDolbyVisionFallback
                )
            } catch {
                logger.error(
                    "format change failed error=\(error.localizedDescription, privacy: .public)"
                )
                playbackRuntime.setUserVisibleIssue(.mediaFormatChangeFailed)
            }
        }
    }

    private func restoreAutomaticFormat() {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        register()
        Task {
            do {
                try await playbackLauncher.resetFormat()
            } catch {
                logger.error(
                    "source format restoration failed error=\(error.localizedDescription, privacy: .public)"
                )
                playbackRuntime.setUserVisibleIssue(.mediaFormatChangeFailed)
            }
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
                        self.logger.error(
                            "subtitle selection failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        self.playbackRuntime.setUserVisibleIssue(.subtitleTrackSelectionFailed)
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
                        self.logger.error(
                            "subtitle disable failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        self.playbackRuntime.setUserVisibleIssue(.subtitleTrackSelectionFailed)
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
                        self.logger.error(
                            "audio selection failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        self.playbackRuntime.setUserVisibleIssue(.audioTrackSelectionFailed)
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
    private let logger = Logger(subsystem: "app.enchron", category: "PlaybackMoreMenu")
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var playbackLauncher
    var body: some View {
        GlassCircleIconMenu(
            systemName: "ellipsis",
            accessibilityLabel: "More",
            accessibilityIdentifier: "PlayerUI-TopAction-more"
        ) {
            Group {
                if !subtitleItems.isEmpty {
                    Menu("Subtitles") {
                        selectableMenuItems(subtitleItems)
                            .onAppear {
                                recordReachability("menu.subtitles")
                            }
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
            .onAppear {
                recordReachability("menu.more")
            }
        }
        .accessibilityLabel("More playback settings")
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
            set: { id in
                recordReachability("menu.item.\(id)")
                items.first(where: { $0.id == id })?.action()
            }
        )
    }

    private func register() {
        appModel.registerControlsInteraction()
    }

    private func recordReachability(_ action: String) {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "reachability top actions delivered action=\(action)"
        )
#endif
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
                        logger.error(
                            "subtitle selection failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        playbackRuntime.setUserVisibleIssue(.subtitleTrackSelectionFailed)
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
                        logger.error(
                            "subtitle disable failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        playbackRuntime.setUserVisibleIssue(.subtitleTrackSelectionFailed)
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
                        logger.error(
                            "audio selection failed error=\(error.localizedDescription, privacy: .public)"
                        )
                        playbackRuntime.setUserVisibleIssue(.audioTrackSelectionFailed)
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
            .enchronListGroupSurface(in: DesignTokens.ShapeToken.panel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerUI-resumeDecision-panel")
        .accessibilityLabel("Resume Playback?")
    }
}
