import SwiftUI
import UniformTypeIdentifiers

public struct FileBrowserView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @State private var isFolderPickerPresented = false
    @State private var isVideoPickerPresented = false

    public init() {}

    private var videoImportTypes: [UTType] {
        var types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie]
        if let mkvType = UTType(filenameExtension: "mkv") {
            types.append(mkvType)
        } else {
            types.append(UTType(importedAs: "org.matroska.mkv"))
        }
        return types
    }
    
    public var body: some View {
        NavigationStack {
            FolderListView(
                files: viewModel.files,
                isLoading: viewModel.isLoading,
                onFileSelected: { file in
                    viewModel.selectFile(file)
                }
            )
            .navigationTitle("Files")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(viewModel.currentRootDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Folder") {
                        Button("Choose Folder...") {
                            isFolderPickerPresented = true
                        }
                        Button("Import Video...") {
                            isVideoPickerPresented = true
                        }
                        Button("Use App Documents") {
                            Task {
                                await viewModel.useDefaultFolder()
                            }
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await viewModel.loadFiles()
                }
            }
            .refreshable {
                await viewModel.loadFiles()
            }
            .fileImporter(
                isPresented: $isFolderPickerPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let folderURL = urls.first else { return }
                    Task {
                        await viewModel.selectLocalFolder(folderURL)
                    }
                case .failure(let error):
                    viewModel.lastErrorMessage = "Folder selection failed: \(error.localizedDescription)"
                    print("[FileBrowser] folder picker failed: \(error)")
                }
            }
            .fileImporter(
                isPresented: $isVideoPickerPresented,
                allowedContentTypes: videoImportTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await viewModel.importLocalFiles(urls)
                    }
                case .failure(let error):
                    viewModel.lastErrorMessage = "Video import failed: \(error.localizedDescription)"
                    print("[FileBrowser] video import failed: \(error)")
                }
            }
            .alert(
                "File Browser Error",
                isPresented: Binding(
                    get: { viewModel.lastErrorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            viewModel.lastErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.lastErrorMessage = nil
                }
            } message: {
                Text(viewModel.lastErrorMessage ?? "Unknown error")
            }
        }
    }
}
