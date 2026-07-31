import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

/// Window playback chrome. Navigation stays at the top while media facts are
/// rendered by `PlayerMediaInfoView` at the lower leading edge of the video.
struct PlayerInfoBarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var launcher

    var body: some View {
        WindowPlaybackTopChrome {
            GlassCircleIconButton.back(
                accessibilityLabel: "Back",
                action: {
                    launcher.stopPlayback()
                },
                accessibilityIdentifier: "PlayerUI-InfoBar-button-back"
            )
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityHint("Stops playback and returns to browser")
        } spatialActions: {
            PlaybackTopActions(
                initialPresentedMenu: initialPresentedMenu,
                canDock: playbackRuntime.canEnterSpatialPresentation
                    && PlaybackPresentationAvailability.canDock(
                        in: appModel.playbackPresentation,
                        isPanoramic: playbackRuntime.effectiveProjectionType.isPanoramic
                    ),
                canApplyFormat: playbackRuntime.canEnterSpatialPresentation,
                canUseFisheye: playbackRuntime.supportsFisheyePresentation,
                resumesPanorama: PlaybackPresentationAvailability.windowShowsPanoramaResume(
                    in: appModel.playbackPresentation,
                    isPanoramic: playbackRuntime.effectiveProjectionType.isPanoramic
                ),
                onDock: dock,
                onApplyFormat: applyFormat,
                onResumePanorama: resumePanorama
            )
        } moreControl: {
            ProductionPlaybackMoreMenu()
        }
    }

    private func resumePanorama() {
        guard playbackRuntime.canEnterSpatialPresentation,
              playbackRuntime.effectiveProjectionType.isPanoramic else { return }
        _ = try? appModel.requestPlaybackPresentation(
            .panorama,
            mediaSessionID: playbackRuntime.activeSessionID,
            wasPlaying: playbackRuntime.productLifecycle == .playing
        )
    }

    private var initialPresentedMenu: PlaybackTopSecondaryMenu? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ENCHRON_UI_TESTING"] == "1",
              let rawValue = environment["ENCHRON_UI_INITIAL_MENU"] else { return nil }
        return PlaybackTopSecondaryMenu(rawValue: rawValue)
    }

    private func dock(in effect: SpatialSceneDomain.EnvironmentEffect) {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        do {
            _ = try appModel.requestPlaybackPresentation(
                .docked,
                effect: effect,
                mediaSessionID: playbackRuntime.activeSessionID,
                wasPlaying: playbackRuntime.productLifecycle == .playing
            )
        } catch {
            playbackRuntime.lastErrorMessage = error.localizedDescription
        }
    }

    private func applyFormat(
        _ projection: PlaybackModel.ProjectionType,
        _ stereo: PlaybackModel.StereoLayout
    ) {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        Task {
            do {
                try await launcher.applyFormat(projection: projection, stereo: stereo)
                if projection != .flat {
                    _ = try appModel.requestPlaybackPresentation(
                        .panorama,
                        mediaSessionID: playbackRuntime.activeSessionID,
                        wasPlaying: playbackRuntime.productLifecycle == .playing
                    )
                }
            } catch {
                playbackRuntime.lastErrorMessage = error.localizedDescription
            }
        }
    }

}

struct PlayerMediaInfoView: View {
    @Environment(PlaybackRuntime.self) private var playbackRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(videoTitle)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let profile = playbackRuntime.displayMediaProfile {
                let parts = formatParts(profile)
                Text(parts.joined(separator: " \u{00B7} "))
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var videoTitle: String {
        playbackRuntime.currentPlaybackURL?.deletingPathExtension().lastPathComponent ?? "Unknown"
    }

    private func formatParts(_ profile: PlaybackModel.MediaProfile) -> [String] {
        var parts: [String] = []

        // Resolution badge (e.g. "4K", "1080p")
        let height = profile.resolution.height
        let width = profile.resolution.width
        if width >= 3840 || height >= 2160 {
            parts.append("4K")
        } else if height >= 1080 {
            parts.append("1080p")
        } else if height >= 720 {
            parts.append("720p")
        } else if height > 0 {
            parts.append("\(height)p")
        }

        // HDR type
        if profile.hdrType != .sdr {
            parts.append(PlaybackInfoFormatter.hdrTypeLabel(profile.hdrType))
        }

        // Codec
        let codec = PlaybackInfoFormatter.videoCodecLabel(profile.videoCodec)
        if codec != "Unknown" {
            parts.append(codec)
        }

        // Spatial Audio — detected from audio track display names per player.html badge
        // Mirrors "4K HDR · HEVC · Spatial Audio" format
        if hasSpatialAudio {
            parts.append("Spatial Audio")
        }

        return parts
    }

    /// Heuristic: any audio track whose display name contains known spatial audio indicators.
    private var hasSpatialAudio: Bool {
        let spatialKeywords = ["atmos", "dts:x", "dts-x", "360", "spatial", "surround"]
        return playbackRuntime.availableAudioTracks.contains { track in
            let lower = track.displayName.lowercased()
            return spatialKeywords.contains { lower.contains($0) }
        }
    }
}
