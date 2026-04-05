import SwiftUI

public struct PlaylistView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(PlaybackLaunchCoordinator.self) private var launcher
    @Environment(\.dismiss) private var dismiss
    private let onClose: (() -> Void)?

    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Playlist")
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
                .hoverEffect(.highlight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(fileBrowsingViewModel.files, id: \.id) { file in
                        let isCurrent = appModel.currentPlaybackURL == file.url

                        Button {
                            Task {
                                do {
                                    let request = try await fileBrowsingViewModel.playbackRequest(for: file)
                                    await MainActor.run {
                                        launcher.beginPlayback(request)
                                        dismissPanel()
                                    }
                                } catch {
                                    await MainActor.run {
                                        fileBrowsingViewModel.lastErrorMessage = "Failed to open \"\(file.name)\": \(error.localizedDescription)"
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isCurrent ? "play.fill" : "play")
                                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)

                                Text(file.name)
                                    .lineLimit(1)
                                    .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)

                                Spacer()

                                if isCurrent {
                                    Image(systemName: "waveform")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect()
    }

    private func dismissPanel() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}
