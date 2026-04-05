import SwiftUI

/// Top info bar for the player control pill.
/// Shows back button, video title, and format metadata badges.
struct PlayerInfoBarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            Button {
                appModel.stopPlayback()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .frame(minWidth: 60, minHeight: 60)
            .contentShape(.rect)
            .accessibilityLabel("Back")
            .accessibilityHint("Stops playback and returns to browser")

            Text(videoTitle)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if let profile = videoViewModel.displayMediaProfile {
                formatMetadataView(profile)
            }
        }
    }

    private var videoTitle: String {
        appModel.currentPlaybackURL?.deletingPathExtension().lastPathComponent ?? "Unknown"
    }

    @ViewBuilder
    private func formatMetadataView(_ profile: PlaybackCoreDomain.MediaProfile) -> some View {
        HStack(spacing: 6) {
            let parts = formatParts(profile)
            Text(parts.joined(separator: " \u{00B7} "))
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func formatParts(_ profile: PlaybackCoreDomain.MediaProfile) -> [String] {
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

        return parts
    }
}
