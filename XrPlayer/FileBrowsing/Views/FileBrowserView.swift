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
        NavigationStack {
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
                
                if !viewModel.savedDataSources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.savedDataSources) { ds in
                                HStack(spacing: 8) {
                                    Button {
                                        Task { await viewModel.connectToDataSource(ds) }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: ds.sourceType == .smb ? "externaldrive.connected.to.line.below" : "network")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            Circle()
                                                .fill(viewModel.activeDataSource?.id == ds.id ? .green : .gray)
                                                .frame(width: 8, height: 8)

                                            Text(ds.name)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .glassBackgroundEffect(in: Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    Button(role: .destructive) {
                                        viewModel.removeDataSource(id: ds.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 60, height: 60)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete \(ds.name)")
                                }
                                .padding(.trailing, 4)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }

                if viewModel.canNavigateUp {
                    HStack {
                        Button {
                            Task {
                                await viewModel.navigateUp()
                            }
                        } label: {
                            Label("Up", systemImage: "chevron.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                FolderListView(
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
                ToolbarItem(placement: .topBarLeading) {
                    Text(viewModel.currentRootDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Folder") {
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

                            if !viewModel.savedDataSources.isEmpty {
                                Divider()
                                ForEach(viewModel.savedDataSources) { ds in
                                    Menu(ds.name) {
                                        Button("Connect") {
                                            Task { await viewModel.connectToDataSource(ds) }
                                        }

                                        Button("Delete", role: .destructive) {
                                            viewModel.removeDataSource(id: ds.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
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
            .navigationDestination(
                isPresented: Binding(
                    get: { viewModel.detailNavigationRequest != nil },
                    set: { isPresented in
                        if !isPresented {
                            viewModel.detailNavigationRequest = nil
                        }
                    }
                )
            ) {
                VideoDetailView()
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
    }
}
