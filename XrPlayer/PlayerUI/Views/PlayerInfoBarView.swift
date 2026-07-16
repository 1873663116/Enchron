import SwiftUI

/// Top info bar for the player control pill.
/// Shows back button, video title, and format metadata badges.
struct PlayerInfoBarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackRuntime.self) private var playbackRuntime
    @Environment(PlaybackLaunchCoordinator.self) private var launcher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            Button {
                launcher.stopPlayback()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, height: 60)
                    .contentShape(.rect(cornerRadius: 12))
            }
            .buttonStyle(.borderless)
            .enchronHoverEffect(.highlight)
            .accessibilityLabel("Back")
            .accessibilityHint("Stops playback and returns to browser")
            .accessibilityIdentifier("PlayerUI-InfoBar-button-back")

            Text(videoTitle)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let profile = playbackRuntime.displayMediaProfile {
                formatMetadataView(profile)
            }

            PlaybackTopActions(
                initialPresentedMenu: initialPresentedMenu,
                canDock: playbackRuntime.canEnterSpatialPresentation,
                canApplyFormat: playbackRuntime.canEnterSpatialPresentation,
                onDock: dock,
                onApplyFormat: applyFormat
            )
        }
    }

    private var videoTitle: String {
        playbackRuntime.currentPlaybackURL?.deletingPathExtension().lastPathComponent ?? "Unknown"
    }

    private var initialPresentedMenu: PlaybackTopSecondaryMenu? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ENCHRON_UI_TESTING"] == "1",
              let rawValue = environment["ENCHRON_UI_INITIAL_MENU"] else { return nil }
        return PlaybackTopSecondaryMenu(rawValue: rawValue)
    }

    private func dock(in environment: SpatialSceneDomain.CinemaEnvironment) {
        guard playbackRuntime.canEnterSpatialPresentation else { return }
        do {
            _ = try appModel.requestPlaybackPresentation(.docked, environment: environment)
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
                try await playbackRuntime.setFormat(projection: projection, stereo: stereo)
                if projection != .flat {
                    _ = try appModel.requestPlaybackPresentation(.panorama)
                }
            } catch {
                playbackRuntime.lastErrorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func formatMetadataView(_ profile: PlaybackModel.MediaProfile) -> some View {
        HStack(spacing: 6) {
            let parts = formatParts(profile)
            Text(parts.joined(separator: " \u{00B7} "))
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
