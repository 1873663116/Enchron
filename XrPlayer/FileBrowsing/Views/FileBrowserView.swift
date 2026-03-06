import SwiftUI
import UniformTypeIdentifiers

public struct FileBrowserView: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @State private var isFolderPickerPresented = false
    @State private var isVideoPickerPresented = false
    @State private var isAddSourcePresented = false

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
                    .background(.secondary.opacity(0.1))
                }

                if let reconnectMessage = viewModel.reconnectStatusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(reconnectMessage)
                            .font(.footnote)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.18))
                }
                
                if !viewModel.savedDataSources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(viewModel.savedDataSources) { ds in
                                Button {
                                    Task { await viewModel.connectToDataSource(ds) }
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(viewModel.activeDataSource?.id == ds.id ? .green : .gray)
                                            .frame(width: 8, height: 8)
                                        Text(ds.name)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(16)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if viewModel.activeDataSource?.id == ds.id {
                                            Task { await viewModel.useDefaultFolder() }
                                        }
                                        viewModel.removeDataSource(id: ds.id)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    Divider()
                }

                FolderListView(
                    files: viewModel.files,
                    isLoading: viewModel.isLoading,
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
                    Menu("Folder") {
                        Section("Local") {
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
                        
                        Section("Remote") {
                            Button("Add Remote Source...") {
                                isAddSourcePresented = true
                            }
                            
                            if !viewModel.savedDataSources.isEmpty {
                                Divider()
                                ForEach(viewModel.savedDataSources) { ds in
                                    Menu(ds.name) {
                                        Button("Connect") {
                                            Task { await viewModel.connectToDataSource(ds) }
                                        }
                                        Button("Remove", role: .destructive) {
                                            if viewModel.activeDataSource?.id == ds.id {
                                                Task { await viewModel.useDefaultFolder() }
                                            }
                                            viewModel.removeDataSource(id: ds.id)
                                        }
                                    }
                                    .labelStyle(.titleOnly)
                                    .overlay(alignment: .trailing) {
                                        if viewModel.activeDataSource?.id == ds.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddSourcePresented) {
                DataSourceConfigView()
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
