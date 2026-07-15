import SwiftUI
import PhotosUI
@preconcurrency import Photos
import UniformTypeIdentifiers

struct FilesScreen: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @Environment(MediaLibraryViewModel.self) private var mediaLibrary

    /// 0 = grid, 1 = list (UC-FILE-34). View-mode is screen-local UI state.
    @State private var viewMode = 0
    @State private var sortKey: SortMenuKey = .name
    @State private var sortOrder: SortMenuOrder = .ascending
    @State private var sourceItems: [SidebarSourceItem] = []
    @State private var presentedSourceConnection: SourceConnectionKind?
    @State private var isBrowsingSource = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var folderToRename: FileBrowsingDomain.LibraryFolder?
    @State private var renamedFolderName = ""
    @State private var folderToRemove: FileBrowsingDomain.LibraryFolder?
    @State private var fileSelectionKind: FileSelectionKind = .files
    @State private var isFileImporterPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    private var totalItemCount: Int {
        if isBrowsingSource {
            return viewModel.displayedFolders.count + viewModel.displayedFiles.count
        }
        return displayedLibraryFolders.count + displayedLibraryReferences.count
    }

    private var isEmpty: Bool {
        if isBrowsingSource {
            return viewModel.files.isEmpty && viewModel.folders.isEmpty && !viewModel.isLoading
        }
        return mediaLibrary.folders.isEmpty && mediaLibrary.references.isEmpty
    }

    private var displayedLibraryFolders: [FileBrowsingDomain.LibraryFolder] {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let folders = query.isEmpty
            ? mediaLibrary.folders
            : mediaLibrary.folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedLibraryReferences: [FileBrowsingDomain.MediaReference] {
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let references = query.isEmpty
            ? mediaLibrary.references
            : mediaLibrary.references.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return references.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sortKey {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .modifiedDate:
                comparison = lhs.modifiedAt == rhs.modifiedAt
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    : (lhs.modifiedAt < rhs.modifiedAt ? .orderedAscending : .orderedDescending)
            case .size:
                comparison = lhs.sizeInBytes == rhs.sizeInBytes
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    : (lhs.sizeInBytes < rhs.sizeInBytes ? .orderedAscending : .orderedDescending)
            }
            return sortOrder == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackgroundEffect(.plate, in: DesignTokens.ShapeToken.panel, displayMode: .always)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FileBrowsing-FilesScreen")
        .onAppear { syncSourceItems() }
        .onChange(of: viewModel.savedDataSources) { _, _ in syncSourceItems() }
        .onChange(of: viewModel.activeDataSource) { _, source in
            if source != nil { isBrowsingSource = true }
            syncSourceItems()
        }
        .sheet(item: $presentedSourceConnection) { kind in
            SourceConnectionSheet(kind: kind)
        }
        .alert("New Library Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
                .accessibilityIdentifier("MediaLibrary-NewFolder-name")
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                mediaLibrary.createFolder(named: newFolderName)
                newFolderName = ""
            }
            .accessibilityIdentifier("MediaLibrary-NewFolder-create")
        }
        .alert(
            "Rename Library Folder",
            isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )
        ) {
            TextField("Folder name", text: $renamedFolderName)
                .accessibilityIdentifier("MediaLibrary-RenameFolder-name")
            Button("Cancel", role: .cancel) { folderToRename = nil }
            Button("Rename") {
                if let folderToRename {
                    mediaLibrary.rename(folderToRename, to: renamedFolderName)
                }
                folderToRename = nil
            }
            .accessibilityIdentifier("MediaLibrary-RenameFolder-confirm")
        }
        .confirmationDialog(
            "Remove this library folder and its references? Original media will not be changed.",
            isPresented: Binding(
                get: { folderToRemove != nil },
                set: { if !$0 { folderToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove from Library", role: .destructive) {
                if let folderToRemove {
                    mediaLibrary.remove(folderToRemove)
                }
                folderToRemove = nil
            }
            Button("Cancel", role: .cancel) { folderToRemove = nil }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: fileSelectionKind.allowedContentTypes,
            allowsMultipleSelection: fileSelectionKind == .files
        ) { result in
            switch result {
            case .success(let urls):
                if fileSelectionKind == .folder, let folder = urls.first {
                    mediaLibrary.addFolder(folder)
                } else {
                    mediaLibrary.addFiles(urls)
                }
            case .failure(let error):
                mediaLibrary.lastErrorMessage = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: nil,
            selectionBehavior: .ordered,
            matching: .videos,
            preferredItemEncoding: .current,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItems) { _, items in
            addSelectedPhotos(items)
        }
        .enchronErrorDialog(
            "File Browser Error",
            message: viewModel.lastErrorMessage ?? "Couldn't load this location. Check the source connection and try again.",
            primaryTitle: "Retry",
            secondaryTitle: "OK",
            isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { if !$0 { viewModel.lastErrorMessage = nil } }
            ),
            identifierPrefix: "FileBrowsing-error",
            onPrimary: { Task { await viewModel.loadFiles() } },
            onSecondary: { viewModel.disconnectAndResetToLocal() }
        )
        .enchronErrorDialog(
            "Media Library Error",
            message: mediaLibrary.lastErrorMessage ?? "The original media source is unavailable.",
            primaryTitle: "OK",
            secondaryTitle: "Dismiss",
            isPresented: Binding(
                get: { mediaLibrary.lastErrorMessage != nil },
                set: { if !$0 { mediaLibrary.lastErrorMessage = nil } }
            ),
            identifierPrefix: "MediaLibrary-error",
            onPrimary: { mediaLibrary.lastErrorMessage = nil },
            onSecondary: { mediaLibrary.lastErrorMessage = nil }
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        SourceSidebar(
            items: $sourceItems,
            title: "Library & Sources",
            containerIdentifier: "FileBrowsing-MainWindow-sidebar",
            identifierPrefix: "FileBrowsing-SourcesSidebar",
            onSelectSource: { id in select(sourceID: id) },
            onAddSource: { type in presentConnection(for: type) },
            onRefresh: { Task { await viewModel.loadFiles() } },
            onDeleteSources: deleteSources
        )
    }

    private func syncSourceItems() {
        var items: [SidebarSourceItem] = [
            SidebarSourceItem(
                id: mediaLibrarySourceID,
                icon: "rectangle.stack.fill",
                title: "Media Library",
                isSelected: !isBrowsingSource,
                isActiveSource: !isBrowsingSource,
                isDeletable: false
            )
        ]
        items += viewModel.savedDataSources.map { ds in
            SidebarSourceItem(
                id: ds.id.uuidString,
                icon: icon(for: ds.sourceType),
                title: ds.name,
                isSelected: viewModel.activeDataSource?.id == ds.id,
                isActiveSource: viewModel.activeDataSource?.id == ds.id
            )
        }
        sourceItems = items
    }

    private func select(sourceID: SidebarSourceItem.ID) {
        if sourceID == mediaLibrarySourceID {
            isBrowsingSource = false
            mediaLibrary.navigateToRoot()
            syncSourceItems()
            return
        }
        guard let ds = viewModel.savedDataSources.first(where: { $0.id.uuidString == sourceID }) else { return }
        Task { await viewModel.connectToDataSource(ds) }
    }

    private func presentConnection(for sourceType: FileBrowsingDomain.SourceType) {
        switch sourceType {
        case .webDAV:
            presentedSourceConnection = .webDAV
        case .smb:
            presentedSourceConnection = .smb
        case .photoLibrary:
            requestPhotosAccessAndPresentPicker()
        case .local:
            fileSelectionKind = .files
            isFileImporterPresented = true
        }
    }

    private func deleteSources(_ ids: Set<SidebarSourceItem.ID>) {
        for id in ids {
            guard let uuid = UUID(uuidString: id) else { continue }
            viewModel.removeDataSource(id: uuid)
        }
    }

    private func icon(for type: FileBrowsingDomain.SourceType) -> String {
        switch type {
        case .local: "externaldrive.fill"
        case .smb: "server.rack"
        case .webDAV: "cloud.fill"
        case .photoLibrary: "photo.on.rectangle"
        }
    }

    private let mediaLibrarySourceID = "media-library"

    // MARK: - Content

    private var contentArea: some View {
        VStack(spacing: 0) {
            topBar
            if !isEmpty {
                itemCountBar
            }
            filesBody
        }
        .padding(.leading, DesignTokens.SourceSidebar.trailingContentGap)
        .padding(.trailing, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var filesBody: some View {
        ZStack {
            currentFolderContent
                // Each folder is its own identity, so changing path cross-fades the
                // listing in/out instead of hard-cutting — the same quick fade used
                // elsewhere. View-mode (grid/list) keeps the identity, so toggling it
                // is unaffected.
                .id(isBrowsingSource ? viewModel.currentRemotePath : mediaLibrary.currentFolderID?.uuidString ?? "media-library-root")
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DesignTokens.AnimationToken.controlsTransition, value: viewModel.currentRemotePath)
    }

    @ViewBuilder
    private var currentFolderContent: some View {
        if isBrowsingSource && viewModel.isLoading && viewModel.files.isEmpty && viewModel.folders.isEmpty {
            loadingState
        } else if isEmpty {
            emptyState
        } else if viewMode == 0 {
            grid
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer(minLength: 0)
            LoadingSpinner()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("FileBrowsing-FilesScreen-loadingState")
        .accessibilityLabel("Loading")
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: "folder")
                .font(DesignTokens.SymbolSize.giant)
                .foregroundStyle(DesignTokens.Surface.supportingText)
            Text("No media here yet")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("FileBrowsing-FilesScreen-emptyState")
        .accessibilityLabel("No media")
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            NavBackForwardCapsuleControl(
                onBack: {
                    if isBrowsingSource {
                        Task { await viewModel.navigateUp() }
                    } else {
                        mediaLibrary.navigateUp()
                    }
                },
                onForward: {
                    if isBrowsingSource { Task { await viewModel.navigateForward() } }
                },
                accessibilityIdentifier: "FileBrowsing-FilesScreen-navBackForward"
            )
            breadcrumb
            Spacer(minLength: DesignTokens.Spacing.xl)
            ViewModeCapsuleControl(
                selection: $viewMode,
                accessibilityIdentifier: "FileBrowsing-FilesScreen-viewMode"
            )
            SortMenuButton(
                sortKey: $sortKey,
                sortOrder: $sortOrder,
                accessibilityIdentifier: "FileBrowsing-FilesScreen-sort"
            )
            .onChange(of: sortKey) { _, _ in applySort() }
            .onChange(of: sortOrder) { _, _ in applySort() }
            manageMenu
            SearchInputCapsule(
                text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
                placeholder: "Search media...",
                accessibilityIdentifier: "FileBrowsing-FilesScreen-search"
            )
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var breadcrumb: some View {
        if !isBrowsingSource {
            let folders = mediaLibrary.breadcrumbFolders
            return PathBreadcrumbMenu(
                path: ["Media Library"] + folders.map(\.name),
                onSelectLevel: { position in
                    if position == 0 {
                        mediaLibrary.navigateToRoot()
                    } else if folders.indices.contains(position - 1) {
                        mediaLibrary.navigate(to: folders[position - 1].id)
                    }
                }
            )
        }
        let segments = viewModel.breadcrumbSegments
        return PathBreadcrumbMenu(
            path: segments.map(\.name),
            onSelectLevel: { position in
                guard position >= 0, position < segments.count else { return }
                let stackIndex = segments[position].index
                Task { await viewModel.navigateToBreadcrumb(index: stackIndex) }
            }
        )
    }

    private var manageMenu: some View {
        Menu {
            Button {
                fileSelectionKind = .files
                isFileImporterPresented = true
            } label: {
                Label("Add Files", systemImage: "doc.badge.plus")
            }
            .accessibilityIdentifier("MediaLibrary-Manage-addFiles")
            Button {
                fileSelectionKind = .folder
                isFileImporterPresented = true
            } label: {
                Label("Add Folder Contents", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("MediaLibrary-Manage-addFolder")
            Button {
                requestPhotosAccessAndPresentPicker()
            } label: {
                Label("Add from Photos", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("MediaLibrary-Manage-addPhotos")
            Divider()
            Button {
                isCreatingFolder = true
            } label: {
                Label("New Library Folder", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("MediaLibrary-Manage-newFolder")
        } label: {
            GlassCircleIconLabel(
                systemName: "ellipsis",
                accessibilityLabel: "Manage media library",
                iconColor: .secondary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manage media library")
        .accessibilityIdentifier("FileBrowsing-Manage-button")
    }

    private var itemCountBar: some View {
        HStack {
            Spacer()
            Text("\(totalItemCount) items")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("FileBrowsing-FilesScreen-itemCount")
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    // MARK: - Grid / List

    private var gridMaxWidth: CGFloat {
        DesignTokens.Card.gridMin * 4 + DesignTokens.Card.gridSpacing * 3
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: DesignTokens.Card.gridMin), spacing: DesignTokens.Card.gridSpacing)
                ],
                alignment: .leading,
                spacing: DesignTokens.Card.gridSpacing
            ) {
                if isBrowsingSource {
                    ForEach(viewModel.displayedFolders) { folder in
                        GridCard.folder(
                            title: folder.name,
                            count: 0,
                            accessibilityIdentifier: "FileBrowsing-grid-folder-\(folder.name)",
                            action: { Task { await viewModel.navigateToFolder(folder) } }
                        )
                    }
                    ForEach(viewModel.displayedFiles) { file in
                        GridCard.video(
                            title: displayTitle(file),
                            fileSize: fileSizeText(file),
                            duration: "",
                            accessibilityIdentifier: "FileBrowsing-grid-video-\(file.name)",
                            action: { viewModel.selectFile(file) }
                        )
                        .contextMenu {
                            if let source = viewModel.activeDataSource {
                                Button("Add to Media Library", systemImage: "plus.rectangle.on.folder") {
                                    mediaLibrary.addSourceFile(
                                        file,
                                        dataSourceID: source.id,
                                        path: file.url.absoluteString
                                    )
                                }
                            }
                        }
                    }
                } else {
                    ForEach(displayedLibraryFolders) { folder in
                        GridCard.folder(
                            title: folder.name,
                            count: mediaLibrary.library.references(in: folder.id).count,
                            accessibilityIdentifier: "MediaLibrary-grid-folder-\(folder.name)",
                            action: { mediaLibrary.open(folder) }
                        )
                        .contextMenu { libraryFolderActions(folder) }
                    }
                    ForEach(displayedLibraryReferences) { reference in
                        GridCard.video(
                            title: displayTitle(reference),
                            fileSize: fileSizeText(reference),
                            duration: "",
                            accessibilityIdentifier: "MediaLibrary-grid-video-\(reference.name)",
                            action: { mediaLibrary.play(reference) }
                        )
                        .contextMenu { libraryReferenceActions(reference) }
                    }
                }
            }
            .frame(maxWidth: gridMaxWidth, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var list: some View {
        ScrollView {
            FileListGroup(
                accessibilityIdentifier: "FileBrowsing-FilesScreen-list",
                items: isBrowsingSource ? sourceListItems : libraryListItems
            )
            .frame(maxWidth: gridMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private var sourceListItems: [FileListGroup.Item] {
        viewModel.displayedFolders.map { folder in
                        FileListGroup.Item.folder(
                            id: "folder-\(folder.id)",
                            title: folder.name,
                            itemCount: 0,
                            action: { Task { await viewModel.navigateToFolder(folder) } }
                        )
                    } + viewModel.displayedFiles.map { file in
                        FileListGroup.Item.video(
                            id: "video-\(file.id)",
                            title: displayTitle(file),
                            fileSize: fileSizeText(file),
                            duration: "",
                            contextActions: sourceFileContextActions(file),
                            action: { viewModel.selectFile(file) }
                        )
                    }
    }

    private var libraryListItems: [FileListGroup.Item] {
        displayedLibraryFolders.map { folder in
            FileListGroup.Item.folder(
                id: "library-folder-\(folder.id)",
                title: folder.name,
                itemCount: mediaLibrary.library.references(in: folder.id).count,
                contextActions: libraryFolderContextActions(folder),
                action: { mediaLibrary.open(folder) }
            )
        } + displayedLibraryReferences.map { reference in
            FileListGroup.Item.video(
                id: "library-video-\(reference.id)",
                title: displayTitle(reference),
                fileSize: fileSizeText(reference),
                duration: "",
                contextActions: libraryReferenceContextActions(reference),
                action: { mediaLibrary.play(reference) }
            )
        }
    }

    // MARK: - Helpers

    private func applySort() {
        let key: FileBrowsingDomain.SortCriteria.Key =
            switch sortKey {
            case .name: .name
            case .modifiedDate: .modifiedDate
            case .size: .size
            }
        let order: FileBrowsingDomain.SortCriteria.Order =
            switch sortOrder {
            case .ascending: .ascending
            case .descending: .descending
            }
        viewModel.sortCriteria = FileBrowsingDomain.SortCriteria(key: key, order: order)
    }

    private func displayTitle(_ file: FileBrowsingDomain.MediaFile) -> String {
        (file.name as NSString).deletingPathExtension
    }

    private func fileSizeText(_ file: FileBrowsingDomain.MediaFile) -> String {
        ByteCountFormatter.string(fromByteCount: file.sizeInBytes, countStyle: .file)
    }

    private func displayTitle(_ reference: FileBrowsingDomain.MediaReference) -> String {
        (reference.name as NSString).deletingPathExtension
    }

    private func fileSizeText(_ reference: FileBrowsingDomain.MediaReference) -> String {
        guard reference.sizeInBytes > 0 else { return "Referenced" }
        return ByteCountFormatter.string(fromByteCount: reference.sizeInBytes, countStyle: .file)
    }

    @ViewBuilder
    private func libraryReferenceActions(_ reference: FileBrowsingDomain.MediaReference) -> some View {
        Menu("Move to", systemImage: "folder") {
            Button("Media Library") { mediaLibrary.move(reference, to: nil) }
            ForEach(mediaLibrary.allFolders) { folder in
                Button(folder.name) { mediaLibrary.move(reference, to: folder.id) }
            }
        }
        Button("Remove from Library", systemImage: "trash", role: .destructive) {
            mediaLibrary.remove(reference)
        }
    }

    @ViewBuilder
    private func libraryFolderActions(_ folder: FileBrowsingDomain.LibraryFolder) -> some View {
        Button("Rename", systemImage: "pencil") { beginRenaming(folder) }
        Button("Remove from Library", systemImage: "trash", role: .destructive) {
            folderToRemove = folder
        }
    }

    private func libraryFolderContextActions(
        _ folder: FileBrowsingDomain.LibraryFolder
    ) -> [FileListGroup.Item.ContextAction] {
        [
            .init(title: "Rename", systemName: "pencil", action: { beginRenaming(folder) }),
            .init(
                title: "Remove from Library",
                systemName: "trash",
                role: .destructive,
                action: { folderToRemove = folder }
            )
        ]
    }

    private func libraryReferenceContextActions(
        _ reference: FileBrowsingDomain.MediaReference
    ) -> [FileListGroup.Item.ContextAction] {
        var actions = [FileListGroup.Item.ContextAction(
            title: "Move to Media Library",
            systemName: "folder",
            action: { mediaLibrary.move(reference, to: nil) }
        )]
        actions += mediaLibrary.allFolders.map { folder in
            .init(
                title: "Move to \(folder.name)",
                systemName: "folder",
                action: { mediaLibrary.move(reference, to: folder.id) }
            )
        }
        actions.append(.init(
            title: "Remove from Library",
            systemName: "trash",
            role: .destructive,
            action: { mediaLibrary.remove(reference) }
        ))
        return actions
    }

    private func sourceFileContextActions(
        _ file: FileBrowsingDomain.MediaFile
    ) -> [FileListGroup.Item.ContextAction] {
        guard let source = viewModel.activeDataSource else { return [] }
        return [.init(
            title: "Add to Media Library",
            systemName: "plus.rectangle.on.folder",
            action: {
                mediaLibrary.addSourceFile(
                    file,
                    dataSourceID: source.id,
                    path: file.url.absoluteString
                )
            }
        )]
    }

    private func beginRenaming(_ folder: FileBrowsingDomain.LibraryFolder) {
        renamedFolderName = folder.name
        folderToRename = folder
    }

    private func requestPhotosAccessAndPresentPicker() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            switch status {
            case .authorized, .limited:
                isPhotosPickerPresented = true
            default:
                mediaLibrary.lastErrorMessage = "Photos access is required to keep persistent video references."
            }
        }
    }

    private func addSelectedPhotos(_ items: [PhotosPickerItem]) {
        let selections = items.compactMap { item -> (localIdentifier: String, name: String)? in
            guard let identifier = item.itemIdentifier else { return nil }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            let name = assets.firstObject
                .flatMap { PHAssetResource.assetResources(for: $0).first?.originalFilename }
                ?? "Photos Video"
            return (identifier, name)
        }
        mediaLibrary.addPhotoItems(selections)
        selectedPhotoItems = []
    }
}

private enum FileSelectionKind {
    case files
    case folder

    var allowedContentTypes: [UTType] {
        switch self {
        case .folder:
            return [.folder]
        case .files:
            let extensions = ["mkv", "webm", "avi", "m2ts", "ts"]
            return [.movie] + extensions.compactMap { UTType(filenameExtension: $0) }
        }
    }
}

private enum SourceConnectionKind: String, Identifiable {
    case webDAV
    case smb

    var id: String { rawValue }

    var sourceType: FileBrowsingDomain.SourceType {
        switch self {
        case .webDAV: .webDAV
        case .smb: .smb
        }
    }

    var title: String {
        switch self {
        case .webDAV: "WebDAV"
        case .smb: "SMB"
        }
    }
}

private struct SourceConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FileBrowsingViewModel.self) private var viewModel

    let kind: SourceConnectionKind

    @State private var name = ""
    @State private var address = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connectAsGuest = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    private var canConnect: Bool {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if kind == .smb && share.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return connectAsGuest || (!username.isEmpty && !password.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("Display name (optional)", text: $name)
                        .accessibilityIdentifier("FileBrowsing-SourceConnection-name")
                    TextField(kind == .webDAV ? "https://server.example/dav/" : "192.168.1.20", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("FileBrowsing-SourceConnection-address")
                    if kind == .smb {
                        TextField("Share name", text: $share)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("FileBrowsing-SourceConnection-share")
                        Toggle("Connect as Guest", isOn: $connectAsGuest)
                            .accessibilityIdentifier("FileBrowsing-SourceConnection-guest")
                    }
                }

                if !connectAsGuest {
                    Section("Credentials") {
                        TextField("Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("FileBrowsing-SourceConnection-username")
                        SecureField("Password", text: $password)
                            .accessibilityIdentifier("FileBrowsing-SourceConnection-password")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("FileBrowsing-SourceConnection-error")
                    }
                }
            }
            .navigationTitle("Add \(kind.title) Source")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isConnecting ? "Connecting…" : "Connect") {
                        Task { await connect() }
                    }
                    .disabled(!canConnect || isConnecting)
                    .accessibilityIdentifier("FileBrowsing-SourceConnection-connect")
                }
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .interactiveDismissDisabled(isConnecting)
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            var connection = try FileBrowsingDomain.ConnectionInfo.remote(
                sourceType: kind.sourceType,
                address: address,
                username: connectAsGuest ? nil : username
            )
            if kind == .smb {
                connection = connection.withSMBShare(
                    share.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            let source = FileBrowsingDomain.DataSource(
                name: sourceName(for: connection),
                sourceType: kind.sourceType,
                connectionInfo: connection
            )
            viewModel.saveCredential(
                for: source,
                username: connectAsGuest ? "guest" : username,
                password: connectAsGuest ? "" : password
            )
            await viewModel.connectToDataSource(source)

            guard viewModel.activeDataSource?.id == source.id else {
                errorMessage = viewModel.lastErrorMessage ?? "Connection failed."
                return
            }

            viewModel.addDataSource(source)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sourceName(for connection: FileBrowsingDomain.ConnectionInfo) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        return connection.host.map { "\(kind.title) · \($0)" } ?? kind.title
    }
}
