import SwiftUI

public struct PlaybackMenuView: View {
    @Environment(WindowVideoViewModel.self) private var videoViewModel
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Playback Settings")
                    .font(.headline)
                Spacer()
                Button {
                    dismissPanel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 60, minHeight: 60)
                .accessibilityLabel("Close Playback Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Audio Tracks")
                    ForEach(videoViewModel.availableAudioTracks) { track in
                        trackRow(
                            title: track.displayName,
                            lang: track.languageCode,
                            isSelected: videoViewModel.currentAudioTrackID == track.id
                        ) {
                            videoViewModel.selectAudioTrack(track)
                            dismissPanel()
                        }
                    }

                    Divider().padding(.vertical, 6)

                    // Subtitles
                    sectionHeader("Subtitles")
                    trackRow(
                        title: "Disable Subtitles",
                        lang: nil,
                        isSelected: videoViewModel.currentSubtitleTrackID == nil
                            || videoViewModel.currentSubtitleTrackID == "no"
                    ) {
                        videoViewModel.selectSubtitleTrack(nil)
                        dismissPanel()
                    }
                    ForEach(videoViewModel.availableSubtitleTracks) { track in
                        trackRow(
                            title: track.displayName,
                            lang: track.languageCode,
                            isSelected: videoViewModel.currentSubtitleTrackID == track.id
                        ) {
                            videoViewModel.selectSubtitleTrack(track)
                            dismissPanel()
                        }
                    }

                    if videoViewModel.isHDRContent {
                        Divider().padding(.vertical, 6)

                        sectionHeader("Video Output")
                        Toggle(isOn: Binding(
                            get: { videoViewModel.isHDROutputEnabled },
                            set: { videoViewModel.setHDREnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HDR Output")
                                    .font(.body)
                                Text(PlaybackInfoFormatter.hdrTypeLabel(
                                    videoViewModel.displayMediaProfile?.hdrType ?? .sdr))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .accessibilityLabel("HDR Output")
                        .accessibilityValue(videoViewModel.isHDROutputEnabled ? "Enabled" : "Disabled")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                }
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func trackRow(
        title: String,
        lang: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                    if let lang {
                        Text(lang)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(isSelected ? ", selected" : "")")
    }

    private func dismissPanel() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
