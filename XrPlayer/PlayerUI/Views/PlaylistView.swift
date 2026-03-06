import SwiftUI

public struct PlaylistView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(FileBrowsingViewModel.self) private var fileBrowsingViewModel
    @Environment(WindowVideoViewModel.self) private var videoViewModel
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(fileBrowsingViewModel.files, id: \.id) { file in
                        let isCurrent = appModel.currentPlaybackURL == file.url

                        Button {
                            appModel.startPlayback(url: file.url)
                            dismissPanel()
                            Task {
                                try? await videoViewModel.play(url: file.url)
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
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 350, height: 500)
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
