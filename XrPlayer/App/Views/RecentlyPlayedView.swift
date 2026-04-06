import SwiftUI

/// Shows recently played videos sorted by last playback time.
///
/// Lives in the App module as a navigation-level assembly view
/// (not PlayerUI or FileBrowsing — see ARCHITECTURE.md module boundaries).
public struct RecentlyPlayedView: View {
    private let progressStore: ProgressStoring

    @State private var recentItems: [PersistenceDomain.PlaybackProgress] = []
    @State private var isLoading = true

    public init(progressStore: ProgressStoring = SwiftDataStore()) {
        self.progressStore = progressStore
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if recentItems.isEmpty {
                ContentUnavailableView(
                    "No Recent Playback",
                    systemImage: "clock",
                    description: Text("Videos you play will appear here. Browse your library to get started.")
                )
            } else {
                List(recentItems, id: \.fileID) { item in
                    recentRow(item)
                }
            }
        }
        .contentMargins(.top, 20, for: .scrollContent)
        .navigationTitle("Recent")
        .task {
            recentItems = await progressStore.loadRecentlyPlayed(limit: 50)
            isLoading = false
        }
    }

    private func recentRow(_ item: PersistenceDomain.PlaybackProgress) -> some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.enchronTertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(for: item.fileID))
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formattedPosition(item.position.seconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .frame(minHeight: 60)
        .contentShape(.rect)
        .accessibilityIdentifier("App-RecentlyPlayed-row-\(item.fileID.rawValue.prefix(16))")
        .accessibilityLabel(displayName(for: item.fileID))
        .accessibilityHint("Last played \(formattedPosition(item.position.seconds))")
    }

    /// Extracts a display name from the FileIdentifier rawValue.
    /// Format: "path|sizeInBytes|fingerprint" — extract filename from path component.
    private func displayName(for fileID: PersistenceDomain.FileIdentifier) -> String {
        let parts = fileID.rawValue.split(separator: "|", maxSplits: 2)
        guard let pathPart = parts.first else { return fileID.rawValue }
        let url = URL(fileURLWithPath: String(pathPart))
        return url.deletingPathExtension().lastPathComponent
    }

    private func formattedPosition(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
