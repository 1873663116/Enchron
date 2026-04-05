import SwiftUI

/// LazyVGrid wrapper that displays folders and video files as visual cards.
/// Replaces the list-based FolderListView in the detail area of FileBrowserView.
struct ContentGridView: View {
    let folders: [FileBrowsingDomain.MediaFolder]
    let files: [FileBrowsingDomain.MediaFile]
    let isLoading: Bool
    let fileWatchedSeconds: [UUID: Double]
    let onFolderSelected: (FileBrowsingDomain.MediaFolder) -> Void
    let onFileSelected: (FileBrowsingDomain.MediaFile) -> Void
    let onFileDeleted: ((FileBrowsingDomain.MediaFile) -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 20)]

    var body: some View {
        if isLoading {
            ProgressView("Loading files...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if folders.isEmpty && files.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    folderCards
                    fileCards
                }
                .padding()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No folders or playable videos found.")
                .font(.headline)
            Text("This location does not currently expose any browsable folders or supported video files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Folder Cards

    private var folderCards: some View {
        ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
            Button {
                onFolderSelected(folder)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(Color.enchronSurfaceContainerHighest)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.yellow)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(DesignTokens.Typography.headline)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Text("Folder")
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(Color.enchronOnSurfaceVariant)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.card))
            .hoverEffect(.lift)
            .accessibilityLabel("\(folder.name), folder")
            .accessibilityHint("Opens folder contents")
            .accessibilitySortPriority(Double(1000 - index))
        }
    }

    // MARK: - File Cards

    private var fileCards: some View {
        ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
            VideoCardView(
                file: file,
                watchedSeconds: fileWatchedSeconds[file.id],
                onTap: { onFileSelected(file) }
            )
            .contextMenu {
                if let onFileDeleted {
                    Button(role: .destructive) {
                        onFileDeleted(file)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .accessibilitySortPriority(Double(500 - index))
        }
    }
}
