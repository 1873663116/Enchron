import SwiftUI

public struct FolderListView: View {
    public let folders: [FileBrowsingDomain.MediaFolder]
    public let files: [FileBrowsingDomain.MediaFile]
    public let isLoading: Bool
    public let fileWatchedSeconds: [UUID: Double]
    public let onFolderSelected: (FileBrowsingDomain.MediaFolder) -> Void
    public let onFileSelected: (FileBrowsingDomain.MediaFile) -> Void
    public let onFileDeleted: ((FileBrowsingDomain.MediaFile) -> Void)?
    
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    public init(
        folders: [FileBrowsingDomain.MediaFolder] = [],
        files: [FileBrowsingDomain.MediaFile],
        isLoading: Bool = false,
        fileWatchedSeconds: [UUID: Double] = [:],
        onFolderSelected: @escaping (FileBrowsingDomain.MediaFolder) -> Void = { _ in },
        onFileSelected: @escaping (FileBrowsingDomain.MediaFile) -> Void,
        onFileDeleted: ((FileBrowsingDomain.MediaFile) -> Void)? = nil
    ) {
        self.folders = folders
        self.files = files
        self.isLoading = isLoading
        self.fileWatchedSeconds = fileWatchedSeconds
        self.onFolderSelected = onFolderSelected
        self.onFileSelected = onFileSelected
        self.onFileDeleted = onFileDeleted
    }
    
    @ViewBuilder
    public var body: some View {
        if isLoading {
            ProgressView("Loading files...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if folders.isEmpty && files.isEmpty {
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
        } else {
            List {
                if folders.isEmpty == false {
                    Section("Folders") {
                        ForEach(folders) { folder in
                            Button {
                                onFolderSelected(folder)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "folder.fill")
                                        .font(.title3)
                                        .foregroundStyle(.yellow)
                                        .frame(width: 40)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(folder.name)
                                            .font(.headline)
                                            .lineLimit(1)

                                        Text("Open folder")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if files.isEmpty == false {
                    Section("Videos") {
                        ForEach(files) { file in
                            Button {
                                onFileSelected(file)
                            } label: {
                                HStack(spacing: 16) {
                                    fileIcon(for: file.fileExtension)
                                        .font(.title)
                                        .foregroundStyle(.tint)
                                        .frame(width: 40)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.name)
                                            .font(.headline)
                                            .lineLimit(1)

                                        HStack {
                                            Text(byteFormatter.string(fromByteCount: file.sizeInBytes))
                                            Text("•")
                                            Text(dateFormatter.string(from: file.modifiedAt))
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                        if let seconds = fileWatchedSeconds[file.id] {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(.orange)
                                                    .frame(width: 6, height: 6)
                                                Text("Watched \(Self.formatWatchedTime(seconds))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let onFileDeleted {
                                    Button(role: .destructive) {
                                        onFileDeleted(file)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
    
    private static func formatWatchedTime(_ totalSeconds: Double) -> String {
        let seconds = Int(totalSeconds)
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func fileIcon(for extension: String) -> Image {
        switch `extension`.lowercased() {
        case "mp4", "mov", "m4v":
            return Image(systemName: "video.fill")
        case "mkv", "webm", "avi":
            return Image(systemName: "film.fill")
        default:
            return Image(systemName: "doc.fill")
        }
    }
}

#Preview {
    FolderListView(
        folders: [
            FileBrowsingDomain.MediaFolder(
                name: "Movies",
                dataSourceID: UUID(),
                path: "/Movies",
                url: URL(fileURLWithPath: "/Movies")
            )
        ],
        files: [
            FileBrowsingDomain.MediaFile(
                name: "Sample Movie.mp4",
                sizeInBytes: 1024 * 1024 * 50,
                modifiedAt: Date(),
                fileExtension: "mp4",
                url: URL(fileURLWithPath: "/sample.mp4")
            )
        ],
        onFolderSelected: { _ in },
        onFileSelected: { _ in }
    )
}
