import DesignSystem
import MediaLibrary
import MediaSource
import SwiftUI
import PhotosUI
@preconcurrency import Photos
import UniformTypeIdentifiers

struct FilesScreen: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel
    @Environment(MediaLibraryViewModel.self) private var mediaLibrary
    @Environment(MediaLibraryUIState.self) private var uiState

    @State private var sourceItems: [SidebarSourceItem] = []
    @State private var presentedSourceConnection: SourceConnectionKind?
    @State private var sourceConnectionName = ""
    @State private var sourceConnectionAddress = ""
    @State private var sourceConnectionUsername = ""
    @State private var sourceConnectionPassword = ""
    @State private var sourceConnectionConnectsAsGuest = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var folderToRename: FileBrowsingDomain.LibraryFolder?
    @State private var renamedFolderName = ""
    @State private var folderToRemove: FileBrowsingDomain.LibraryFolder?
    @State private var fileSelectionKind: FileSelectionKind = .files
    @State private var isFileImporterPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var mediaReferenceSelectionIsActive = false
    @State private var selectedMediaReferenceIDs: Set<UUID> = []
    @State private var isBatchRemoveConfirmationPresented = false

    private var sourceSelection: MediaLibraryUIState.SourceSelection {
        get { uiState.sourceSelection }
        nonmutating set { uiState.sourceSelection = newValue }
    }

    private var isBrowsingSource: Bool { sourceSelection.isDataSource }

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
        let folders = mediaLibrary.folders.filter {
            MediaLibrarySearch.matches($0, query: viewModel.searchText)
        }
        return folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedLibraryReferences: [FileBrowsingDomain.MediaReference] {
        let references = mediaLibrary.references.filter {
            MediaLibrarySearch.matches($0, query: viewModel.searchText)
        }
        return references.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch uiState.sortCriteria.key {
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
            return uiState.sortCriteria.order == .ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if uiState.sidebarIsVisible {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            contentArea
        }
        .animation(DesignTokens.AnimationToken.controlsTransition, value: uiState.sidebarIsVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FileBrowsing-FilesScreen")
        .onAppear { syncSourceItems() }
        .onChange(of: viewModel.savedDataSources) { _, _ in syncSourceItems() }
        .onChange(of: viewModel.activeDataSource) { _, _ in
            endMediaReferenceSelection()
            syncSourceItems()
        }
        .onChange(of: mediaLibrary.currentFolderID) { _, _ in
            endMediaReferenceSelection()
        }
        .sheet(item: $presentedSourceConnection) { kind in
            ConnectionFormPanel(
                kind: kind,
                name: $sourceConnectionName,
                address: $sourceConnectionAddress,
                username: $sourceConnectionUsername,
                password: $sourceConnectionPassword,
                connectsAsGuest: $sourceConnectionConnectsAsGuest,
                accessibilityIdentifierPrefix: "FileBrowsing-SourceConnection",
                onConnect: connect,
                onCancel: dismissSourceConnection,
                onConnected: dismissSourceConnection
            )
        }
        .alert("New Library Folder", isPresented: $isCreatingFolder) {
            TextField("Folder name", text: $newFolderName)
                .accessibilityIdentifier("MediaLibrary-NewFolder-name")
            Button("Cancel") { newFolderName = "" }
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
            Button("Cancel") { folderToRename = nil }
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
        .confirmationDialog(
            "Remove \(selectedMediaReferenceIDs.count) selected items from the Media Library? Original media will not be changed.",
            isPresented: $isBatchRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Selected", role: .destructive) {
                mediaLibrary.removeReferences(withIDs: selectedMediaReferenceIDs)
                endMediaReferenceSelection()
            }
            .accessibilityIdentifier("MediaLibrary-MultiSelect-confirmDelete")
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: fileSelectionKind.allowedContentTypes,
            allowsMultipleSelection: fileSelectionKind == .files
        ) { result in
            switch result {
            case .success(let urls):
                if fileSelectionKind == .folder, let folder = urls.first {
                    Task { await mediaLibrary.addFolder(folder) }
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
            onSecondary: { viewModel.dismissCurrentError() }
        )
        .alert(
            "Media Library Error",
            isPresented: Binding(
                get: { mediaLibrary.lastErrorMessage != nil },
                set: { if !$0 { mediaLibrary.lastErrorMessage = nil } }
            )
        ) {
            Button("OK") { mediaLibrary.lastErrorMessage = nil }
                .accessibilityIdentifier("MediaLibrary-error-dismiss")
        } message: {
            Text(
                mediaLibrary.lastErrorMessage
                    ?? "The original media source is unavailable."
            )
        }
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
            onImportFolder: presentFolderImporter,
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
                isSelected: sourceSelection == .mediaLibrary,
                isActiveSource: false,
                isDeletable: false
            )
        ]
        items += viewModel.savedDataSources.map { ds in
            SidebarSourceItem(
                id: ds.id.uuidString,
                icon: icon(for: ds.sourceType),
                title: ds.name,
                isSelected: sourceSelection == .dataSource(ds.id),
                isActiveSource: viewModel.activeDataSource?.id == ds.id
            )
        }
        sourceItems = items
    }

    private func select(sourceID: SidebarSourceItem.ID) {
        endMediaReferenceSelection()
        if sourceID == mediaLibrarySourceID {
            sourceSelection = .mediaLibrary
            mediaLibrary.navigateToRoot()
            syncSourceItems()
            return
        }
        guard let ds = viewModel.savedDataSources.first(where: { $0.id.uuidString == sourceID }) else { return }
        sourceSelection = .dataSource(ds.id)
        syncSourceItems()
        Task { await viewModel.connectToDataSource(ds) }
    }

    private func presentConnection(for sourceType: FileBrowsingDomain.SourceType) {
        switch sourceType {
        case .webDAV:
            resetSourceConnectionFields()
            presentedSourceConnection = .webDAV
        case .smb:
            resetSourceConnectionFields()
            presentedSourceConnection = .smb
        case .photoLibrary:
            requestPhotosAccessAndPresentPicker()
        case .local:
            fileSelectionKind = .files
            isFileImporterPresented = true
        }
    }

    private func presentFolderImporter() {
        fileSelectionKind = .folder
        isFileImporterPresented = true
    }

    private func resetSourceConnectionFields() {
        sourceConnectionName = ""
        sourceConnectionAddress = ""
        sourceConnectionUsername = ""
        sourceConnectionPassword = ""
        sourceConnectionConnectsAsGuest = false
    }

    private func dismissSourceConnection() {
        presentedSourceConnection = nil
    }

    private func connect(
        _ request: SourceConnectionRequest
    ) async -> SourceConnectionOutcome {
        do {
            let connection = try FileBrowsingDomain.ConnectionInfo.remote(
                sourceType: request.kind.sourceType,
                address: request.address,
                username: request.connectsAsGuest ? nil : request.username
            )
            let source = FileBrowsingDomain.DataSource(
                name: sourceName(for: request, connection: connection),
                sourceType: request.kind.sourceType,
                connectionInfo: connection
            )
            let credential = StorageCredential(
                username: request.connectsAsGuest ? "guest" : request.username,
                password: request.connectsAsGuest ? "" : request.password
            )
            await viewModel.connectToDataSource(source, credential: credential)

            guard viewModel.activeDataSource?.id == source.id,
                  viewModel.lastErrorMessage == nil
            else {
                let message = viewModel.lastErrorMessage ?? "Connection failed."
                return message.localizedCaseInsensitiveContains("timed out")
                    ? .timedOut(message: message)
                    : .failed(message: message)
            }

            do {
                try viewModel.saveCredential(
                    for: source,
                    username: credential.username,
                    password: credential.password
                )
            } catch {
                await viewModel.useDefaultFolder()
                throw error
            }
            viewModel.addDataSource(source)
            sourceSelection = .dataSource(source.id)
            syncSourceItems()
            return .connected
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    private func sourceName(
        for request: SourceConnectionRequest,
        connection: FileBrowsingDomain.ConnectionInfo
    ) -> String {
        if !request.name.isEmpty {
            return request.name
        }
        return connection.host.map { "\(request.kind.title) · \($0)" }
            ?? request.kind.title
    }

    private func deleteSources(_ ids: Set<SidebarSourceItem.ID>) {
        if let selectedDataSourceID = sourceSelection.dataSourceID,
           ids.contains(selectedDataSourceID.uuidString) {
            sourceSelection = .mediaLibrary
            mediaLibrary.navigateToRoot()
        }
        for id in ids {
            guard let uuid = UUID(uuidString: id) else { continue }
            viewModel.removeDataSource(id: uuid)
        }
        syncSourceItems()
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
        } else if uiState.viewMode == .grid {
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
            SidebarToggleButton(
                isVisible: sidebarVisibilityBinding,
                accessibilityIdentifier: "FileBrowsing-FilesScreen-sidebarToggle"
            )
            NavBackForwardCapsuleControl(
                canGoBack: isBrowsingSource
                    ? viewModel.canNavigateUp
                    : mediaLibrary.canNavigateBack,
                canGoForward: isBrowsingSource
                    ? viewModel.canNavigateForward
                    : mediaLibrary.canNavigateForward,
                onBack: {
                    if isBrowsingSource {
                        Task { await viewModel.navigateUp() }
                    } else {
                        mediaLibrary.navigateBack()
                    }
                },
                onForward: {
                    if isBrowsingSource {
                        Task { await viewModel.navigateForward() }
                    } else {
                        mediaLibrary.navigateForward()
                    }
                },
                accessibilityIdentifier: "FileBrowsing-FilesScreen-navBackForward"
            )
            breadcrumb
            Spacer(minLength: DesignTokens.Spacing.xl)
            if mediaReferenceSelectionIsActive {
                mediaReferenceSelectionControls
            } else {
                ViewModeCapsuleControl(
                    selection: viewModeBinding,
                    accessibilityIdentifier: "FileBrowsing-FilesScreen-viewMode"
                )
                SortMenuButton(
                    sortKey: sortKeyBinding,
                    sortOrder: sortOrderBinding,
                    accessibilityIdentifier: "FileBrowsing-FilesScreen-sort"
                )
                manageMenu
                SearchInputCapsule(
                    text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
                    placeholder: "Search media...",
                    accessibilityIdentifier: "FileBrowsing-FilesScreen-search"
                )
            }
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
                },
                accessibilityIdentifier: "MediaLibrary-Breadcrumb-current"
            )
        }
        let segments = viewModel.breadcrumbSegments
        return PathBreadcrumbMenu(
            path: segments.map(\.name),
            onSelectLevel: { position in
                guard position >= 0, position < segments.count else { return }
                let stackIndex = segments[position].index
                Task { await viewModel.navigateToBreadcrumb(index: stackIndex) }
            },
            accessibilityIdentifier: "FileBrowsing-Breadcrumb-current"
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
                presentFolderImporter()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
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
            if !isBrowsingSource {
                Divider()
                Button {
                    beginMediaReferenceSelection()
                } label: {
                    Label("Select Multiple", systemImage: "checkmark.circle")
                }
                .disabled(displayedLibraryReferences.isEmpty)
                .accessibilityIdentifier("MediaLibrary-Manage-selectMultiple")
            }
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

    private var mediaReferenceSelectionControls: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text("\(selectedMediaReferenceIDs.count) selected")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("MediaLibrary-MultiSelect-count")

            Menu {
                Button("Media Library") {
                    moveSelectedMediaReferences(to: nil)
                }
                ForEach(mediaLibrary.allFolders) { folder in
                    Button(folder.name) {
                        moveSelectedMediaReferences(to: folder.id)
                    }
                }
            } label: {
                Label("Move To", systemImage: "folder")
            }
            .disabled(selectedMediaReferenceIDs.isEmpty)
            .accessibilityIdentifier("MediaLibrary-MultiSelect-move")

            Button(role: .destructive) {
                isBatchRemoveConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedMediaReferenceIDs.isEmpty)
            .accessibilityIdentifier("MediaLibrary-MultiSelect-delete")

            Button("Done") {
                endMediaReferenceSelection()
            }
            .accessibilityIdentifier("MediaLibrary-MultiSelect-done")
        }
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
                            count: nil,
                            accessibilityIdentifier: "FileBrowsing-grid-folder-\(folder.name)",
                            action: { Task { await viewModel.navigateToFolder(folder) } }
                        )
                    }
                    ForEach(viewModel.displayedFiles) { file in
                        GridCard.video(
                            title: displayTitle(file),
                            fileSize: fileSizeText(file),
                            duration: "",
                            watchedProgress: viewModel.fileViewingStates[file.id]?.progress,
                            accessibilityIdentifier: "FileBrowsing-grid-video-\(file.name)",
                            action: { viewModel.selectFile(file) }
                        )
                        .contextMenu {
                            if let source = viewModel.activeDataSource {
                                Button("Add to Media Library", systemImage: "plus.rectangle.on.folder") {
                                    mediaLibrary.addSourceFile(
                                        file,
                                        dataSource: source,
                                        path: file.url.path
                                    )
                                }
                            }
                        }
                    }
                } else {
                    ForEach(displayedLibraryFolders) { folder in
                        GridCard.folder(
                            title: folder.name,
                            count: mediaLibrary.library.folders(in: folder.id).count
                                + mediaLibrary.library.references(in: folder.id).count,
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
                            watchedProgress: mediaLibrary.referenceViewingStates[reference.id]?.progress,
                            accessibilityIdentifier: "MediaLibrary-grid-video-\(reference.name)",
                            selectionEnabled: mediaReferenceSelectionIsActive,
                            isSelected: selectedMediaReferenceIDs.contains(reference.id),
                            action: { activateMediaReference(reference) }
                        )
                        .contextMenu { libraryReferenceActions(reference) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var list: some View {
        ScrollView {
            FileListGroup(
                accessibilityIdentifier: "FileBrowsing-FilesScreen-list",
                items: isBrowsingSource ? sourceListItems : libraryListItems
            )
            .frame(maxWidth: .infinity, alignment: .leading)
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
                            itemCount: nil,
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
                itemCount: mediaLibrary.library.folders(in: folder.id).count
                    + mediaLibrary.library.references(in: folder.id).count,
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
                selectionEnabled: mediaReferenceSelectionIsActive,
                isSelected: selectedMediaReferenceIDs.contains(reference.id),
                action: { activateMediaReference(reference) }
            )
        }
    }

    // MARK: - Helpers

    private var sidebarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { uiState.sidebarIsVisible },
            set: { uiState.sidebarIsVisible = $0 }
        )
    }

    private var viewModeBinding: Binding<Int> {
        Binding(
            get: { uiState.viewMode == .grid ? 0 : 1 },
            set: { uiState.viewMode = $0 == 0 ? .grid : .list }
        )
    }

    private var sortKeyBinding: Binding<SortMenuKey> {
        Binding(
            get: {
                switch uiState.sortCriteria.key {
                case .name: .name
                case .modifiedDate: .modifiedDate
                case .size: .size
                }
            },
            set: { key in
                let domainKey: FileBrowsingDomain.SortCriteria.Key = switch key {
                case .name: .name
                case .modifiedDate: .modifiedDate
                case .size: .size
                }
                uiState.sortCriteria = .init(
                    key: domainKey,
                    order: uiState.sortCriteria.order
                )
            }
        )
    }

    private var sortOrderBinding: Binding<SortMenuOrder> {
        Binding(
            get: {
                switch uiState.sortCriteria.order {
                case .ascending: .ascending
                case .descending: .descending
                }
            },
            set: { order in
                let domainOrder: FileBrowsingDomain.SortCriteria.Order = switch order {
                case .ascending: .ascending
                case .descending: .descending
                }
                uiState.sortCriteria = .init(
                    key: uiState.sortCriteria.key,
                    order: domainOrder
                )
            }
        )
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

    private func beginMediaReferenceSelection() {
        selectedMediaReferenceIDs.removeAll()
        mediaReferenceSelectionIsActive = true
    }

    private func endMediaReferenceSelection() {
        mediaReferenceSelectionIsActive = false
        selectedMediaReferenceIDs.removeAll()
        isBatchRemoveConfirmationPresented = false
    }

    private func activateMediaReference(_ reference: FileBrowsingDomain.MediaReference) {
        AppModel.recordProbe(
            "libraryTap name=\(reference.name) selectionActive=\(mediaReferenceSelectionIsActive)"
        )
        guard mediaReferenceSelectionIsActive else {
            mediaLibrary.play(reference)
            return
        }
        if !selectedMediaReferenceIDs.insert(reference.id).inserted {
            selectedMediaReferenceIDs.remove(reference.id)
        }
    }

    private func moveSelectedMediaReferences(to folderID: UUID?) {
        mediaLibrary.moveReferences(withIDs: selectedMediaReferenceIDs, to: folderID)
        endMediaReferenceSelection()
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
                    dataSource: source,
                    path: file.url.path
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
