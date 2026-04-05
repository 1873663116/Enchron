import SwiftUI
import UniformTypeIdentifiers

public struct FileBrowserView: View {
    private enum RemoteSourceDraft: String, Identifiable {
        case webDAV
        case smb

        var id: String { rawValue }

        var sourceType: FileBrowsingDomain.SourceType {
            switch self {
            case .webDAV:
                return .webDAV
            case .smb:
                return .smb
            }
        }
    }

    @Environment(FileBrowsingViewModel.self) private var viewModel
    @State private var isFolderPickerPresented = false
    @State private var isVideoPickerPresented = false
    @State private var remoteSourceDraft: RemoteSourceDraft?

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
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .sheet(item: $remoteSourceDraft) { draft in
            DataSourceConfigView(sourceType: draft.sourceType)
                .environment(viewModel)
        }
        .onAppear {
            Task {
                await viewModel.loadFiles()
            }
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
            Button("Retry") {
                viewModel.lastErrorMessage = nil
                Task { await viewModel.loadFiles() }
            }
            Button("OK", role: .cancel) {
                viewModel.lastErrorMessage = nil
            }
        } message: {
            Text(viewModel.lastErrorMessage ?? "Unknown error")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        FileBrowserSidebar()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Add Source") {
                        Section("Local") {
                            Button("Choose Folder...") {
                                isFolderPickerPresented = true
                            }
                            Button("Import Video...") {
                                isVideoPickerPresented = true
                            }
                            Button("Photo Library...") {
                                let ds = FileBrowsingDomain.DataSource(
                                    id: UUID(),
                                    name: "Photo Library",
                                    sourceType: .photoLibrary,
                                    connectionInfo: .init(sourceType: .photoLibrary)
                                )
                                Task { await viewModel.connectToDataSource(ds) }
                            }
                            Button("Use App Documents") {
                                Task {
                                    await viewModel.useDefaultFolder()
                                }
                            }
                        }

                        Section("Remote") {
                            Button("Add WebDAV Server...") {
                                remoteSourceDraft = .webDAV
                            }

                            Button("Add SMB Server...") {
                                remoteSourceDraft = .smb
                            }
                        }
                    }
                }
            }
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if let active = viewModel.activeDataSource {
                HStack {
                    Image(systemName: "network")
                    Text("Connected to \(active.name)")
                        .font(.subheadline)
                    Spacer()
                    Button("Disconnect") {
                        Task {
                            await viewModel.useDefaultFolder()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            BreadcrumbView()
            FilterPillsView()

            ContentGridView(
                folders: viewModel.folders,
                files: viewModel.files,
                isLoading: viewModel.isLoading,
                fileWatchedSeconds: viewModel.fileWatchedSeconds,
                onFolderSelected: { folder in
                    Task {
                        await viewModel.navigateToFolder(folder)
                    }
                },
                onFileSelected: { file in
                    viewModel.selectFile(file)
                },
                onFileDeleted: viewModel.isInDocumentsFolder ? { file in
                    Task { await viewModel.deleteFile(file) }
                } : nil
            )
        }
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Sort By") {
                        Button {
                            viewModel.sortCriteria = FileBrowsingDomain.SortCriteria(key: .name, order: viewModel.sortCriteria.key == .name && viewModel.sortCriteria.order == .ascending ? .descending : .ascending)
                        } label: {
                            Label("Name", systemImage: viewModel.sortCriteria.key == .name ? (viewModel.sortCriteria.order == .ascending ? "chevron.up" : "chevron.down") : "")
                        }
                        Button {
                            viewModel.sortCriteria = FileBrowsingDomain.SortCriteria(key: .modifiedDate, order: viewModel.sortCriteria.key == .modifiedDate && viewModel.sortCriteria.order == .descending ? .ascending : .descending)
                        } label: {
                            Label("Date Modified", systemImage: viewModel.sortCriteria.key == .modifiedDate ? (viewModel.sortCriteria.order == .ascending ? "chevron.up" : "chevron.down") : "")
                        }
                        Button {
                            viewModel.sortCriteria = FileBrowsingDomain.SortCriteria(key: .size, order: viewModel.sortCriteria.key == .size && viewModel.sortCriteria.order == .descending ? .ascending : .descending)
                        } label: {
                            Label("Size", systemImage: viewModel.sortCriteria.key == .size ? (viewModel.sortCriteria.order == .ascending ? "chevron.up" : "chevron.down") : "")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort files")
            }
        }
        .refreshable {
            await viewModel.loadFiles()
        }
    }
}
