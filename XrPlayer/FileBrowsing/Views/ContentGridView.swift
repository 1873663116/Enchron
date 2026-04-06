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

    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 20, alignment: .top)]

    var body: some View {
        if isLoading {
            skeletonGrid
        } else if folders.isEmpty && files.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    folderCards
                    fileCards
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Skeleton Loading State

    @State private var shimmerOpacity: Double = 0.4

    private var skeletonGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonCardView()
                        .opacity(shimmerOpacity)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: shimmerOpacity
                        )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onAppear {
            shimmerOpacity = 0.9
        }
        .accessibilityIdentifier("FileBrowsing-ContentGrid-skeleton")
        .accessibilityLabel("Loading content")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(DesignTokens.SymbolSize.giant)
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
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    // MARK: - Folder Cards

    private var folderCards: some View {
        ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
            Button {
                onFolderSelected(folder)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .fill(Color.enchronSurfaceContainerHighest)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay {
                            Image(systemName: "folder.fill")
                                .font(DesignTokens.SymbolSize.card)
                                .foregroundStyle(.yellow)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(folder.name)
                            .font(DesignTokens.Typography.headline)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Text("Folder")
                            .font(DesignTokens.Typography.metadata)
                            .foregroundStyle(Color.enchronOnSurfaceVariant.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(minHeight: 80, alignment: .top)
                }
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
                .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
                .hoverEffect(.lift)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.card))
            .accessibilityIdentifier("FileBrowsing-ContentGrid-button-folder-\(folder.id)")
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
