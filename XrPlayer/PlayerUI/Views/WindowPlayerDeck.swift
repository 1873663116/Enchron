import SwiftUI

struct WindowPlayerDeckView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    var body: some View {
        FusedPlayerPanel(
            live: live,
            onInteraction: register
        )
        .onHover { appModel.setControlsFocused($0) }
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
        let remaining = max(0, duration - position.seconds)
        return FusedPlayerPanelLive(
            presentation: appModel.playbackPresentation,
            canDock: playbackRuntime.canEnterSpatialPresentation,
            canEnterPanorama: playbackRuntime.canEnterSpatialPresentation
                && appModel.effectiveProjectionType.isPanoramic,
            isPlaying: playbackRuntime.playbackState == .playing,
            showsReplay: playbackRuntime.playbackState == .ended,
            progress: duration > 0 ? CGFloat(position.seconds / duration) : 0,
            elapsedLabel: PlaybackTimeFormatter.clock(position.seconds),
            remainingLabel: "-" + PlaybackTimeFormatter.clock(remaining),
            duration: duration,
            framesPerSecond: playbackRuntime.displayMediaProfile?.frameRate ?? 0,
            onPlayPause: { self.register(); self.togglePlayPause() },
            onSkipBackward: { self.register(); self.playbackRuntime.skip(by: -10) },
            onSkipForward: { self.register(); self.playbackRuntime.skip(by: 10) },
            onSeek: { p in
                self.register()
                self.playbackRuntime.seek(to: Double(p) * duration)
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
            subtitleItems: subtitleItems,
            audioItems: audioItems,
            speedItems: speedItems,
            episodeItems: []
        )
    }

    private func enterPlaybackPresentation(_ presentation: PlaybackPresentation) {
        register()
        guard presentation != appModel.playbackPresentation,
              appModel.immersiveSpaceState != .inTransition else { return }
        if presentation != .window {
            guard playbackRuntime.canEnterSpatialPresentation else { return }
        }
        if presentation == .panorama {
            guard appModel.effectiveProjectionType.isPanoramic else { return }
        }
        _ = try? appModel.requestPlaybackPresentation(presentation)
    }

    private func togglePlayPause() {
        switch playbackRuntime.playbackState {
        case .ended: playbackRuntime.replay()
        case .playing: playbackRuntime.pause()
        default: playbackRuntime.resume()
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
                isSelected: appModel.playbackSpeed == speed
            ) {
                self.register()
                self.playbackRuntime.setSpeed(speed)
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
