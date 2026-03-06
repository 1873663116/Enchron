import SwiftUI

public struct FolderListView: View {
    public let files: [FileBrowsingDomain.MediaFile]
    public let isLoading: Bool
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
        files: [FileBrowsingDomain.MediaFile],
        isLoading: Bool = false,
        onFileSelected: @escaping (FileBrowsingDomain.MediaFile) -> Void,
        onFileDeleted: ((FileBrowsingDomain.MediaFile) -> Void)? = nil
    ) {
        self.files = files
        self.isLoading = isLoading
        self.onFileSelected = onFileSelected
        self.onFileDeleted = onFileDeleted
    }
    
    @ViewBuilder
    public var body: some View {
        if isLoading {
            ProgressView("Loading files...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            VStack(spacing: 20) {
                Image(systemName: "video.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("No playable videos found.")
                    .font(.headline)
                Text("Add videos to your Movies folder to see them here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(files) { file in
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
            .listStyle(.plain)
        }
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
        files: [
            FileBrowsingDomain.MediaFile(
                name: "Sample Movie.mp4",
                sizeInBytes: 1024 * 1024 * 50,
                modifiedAt: Date(),
                fileExtension: "mp4",
                url: URL(fileURLWithPath: "/sample.mp4")
            )
        ],
        onFileSelected: { _ in }
    )
}
