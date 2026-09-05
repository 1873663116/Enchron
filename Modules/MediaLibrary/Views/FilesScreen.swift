import DesignSystem
import MediaSource
import SwiftUI

public struct FilesScreen: View {
    static let removeFolderConfirmation = "Remove this library folder and its subfolders? Their media references will move to the parent location. Original media will not be changed."

    @Environment(FileBrowsingViewModel.self) private var viewModel
    @Environment(MediaLibraryViewModel.self) private var mediaLibrary
    @Environment(MediaLibraryUIState.self) private var uiState
    @Bindable private var state: FilesScreenViewState

    private let inputs: FilesScreenInputs

    public init(
        state: FilesScreenViewState,
        inputs: FilesScreenInputs
    ) {
        self.state = state
        self.inputs = inputs
    }

    private var sourceItems: [SidebarSourceItem] {
        get { state.sourceItems }
        nonmutating set { state.sourceItems = newValue }
    }

    private var presentedSourceConnection: SourceConnectionKind? {
        get { state.presentedSourceConnection }
        nonmutating set { state.presentedSourceConnection = newValue }
    }

    private var sourceConnectionDraft: SourceConnectionDraft {
        get { state.sourceConnectionDraft }
        nonmutating set { state.sourceConnectionDraft = newValue }
    }

    private var sourceConnectionDraftKind: SourceConnectionKind? {
        get { state.sourceConnectionDraftKind }
        nonmutating set { state.sourceConnectionDraftKind = newValue }
    }

    private var isCreatingFolder: Bool {
        get { state.isCreatingFolder }
        nonmutating set { state.isCreatingFolder = newValue }
    }

    private var newFolderName: String {
        get { state.newFolderName }
        nonmutating set { state.newFolderName = newValue }
    }

    private var folderToRename: FileBrowsingDomain.LibraryFolder? {
        get { state.folderToRename }
        nonmutating set { state.folderToRename = newValue }
    }

    private var renamedFolderName: String {
        get { state.renamedFolderName }
        nonmutating set { state.renamedFolderName = newValue }
    }

    private var folderToRemove: FileBrowsingDomain.LibraryFolder? {
        get { state.folderToRemove }
        nonmutating set { state.folderToRemove = newValue }
    }

    private var mediaReferenceSelectionIsActive: Bool {
        get { state.mediaReferenceSelectionIsActive }
        nonmutating set { state.mediaReferenceSelectionIsActive = newValue }
    }

    private var selectedMediaReferenceIDs: Set<UUID> {
        get { state.selectedMediaReferenceIDs }
        nonmutating set { state.selectedMediaReferenceIDs = newValue }
    }

    private var isBatchRemoveConfirmationPresented: Bool {
        get { state.isBatchRemoveConfirmationPresented }
        nonmutating set { state.isBatchRemoveConfirmationPresented = newValue }
    }

    private var sourceSelection: MediaLibraryUIState.SourceSelection {
        get { uiState.sourceSelection }
        nonmutating set { uiState.sourceSelection = newValue }
    }

    private var isBrowsingSource: Bool { sourceSelection.isDataSource }

    private var newFolderNameBinding: Binding<String> {
        Binding(
            get: { newFolderName },
            set: {
                recordReachability(.newFolderNameChanged)
                newFolderName = $0
            }
        )
    }

    private var renamedFolderNameBinding: Binding<String> {
        Binding(
            get: { renamedFolderName },
            set: {
                recordReachability(.renameFolderNameChanged)
                renamedFolderName = $0
            }
        )
    }

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

    public var body: some View {
        SidebarSplitLayout(sidebarIsVisible: uiState.sidebarIsVisible) {
            sidebar
        } content: {
            contentArea
        }
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
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest else {
                return
            }
            handleDebugMenuSelection(request)
        }
#endif
        .sheet(
            item: $state.presentedSourceConnection,
            onDismiss: {
                inputs.onModalEvent(.sourceConnectionDismissed)
                sourceConnectionDraft.clearAfterDismissal()
            },
            content: { kind in
                ConnectionFormPanel(
                    kind: kind,
                    name: $state.sourceConnectionDraft.name,
                    address: $state.sourceConnectionDraft.address,
                    username: $state.sourceConnectionDraft.username,
                    password: $state.sourceConnectionDraft.password,
                    connectsAsGuest: $state.sourceConnectionDraft.connectsAsGuest,
                    accessibilityIdentifierPrefix: kind == .smb
                        ? "FileBrowsing-SourceConnection-smb"
                        : "FileBrowsing-SourceConnection-webDAV",
                    guestAccessibilityIdentifier: "FileBrowsing-SourceConnection-smb-guest",
                    onConnect: connect,
                    onCancel: {
                        recordReachability(
                            .sourceConnection(kind, .cancel)
                        )
                        dismissSourceConnection()
                    },
                    onConnected: completeSourceConnection
                )
                .onAppear {
                    inputs.onModalEvent(
                        .sourceConnectionPresented(
                            dismiss: { state.presentedSourceConnection = nil }
                        )
                    )
                }
                .onChange(of: sourceConnectionDraft.name) { _, _ in
                    recordReachability(.sourceConnection(kind, .name))
                }
                .onChange(of: sourceConnectionDraft.address) { _, _ in
                    recordReachability(.sourceConnection(kind, .address))
                }
                .onChange(of: sourceConnectionDraft.username) { _, _ in
                    recordReachability(.sourceConnection(kind, .username))
                }
                .onChange(of: sourceConnectionDraft.password) { _, _ in
                    recordReachability(.sourceConnection(kind, .password))
                }
                .onChange(of: sourceConnectionDraft.connectsAsGuest) { _, _ in
                    recordReachability(.sourceConnection(kind, .guest))
                }
            }
        )
        .alert("New Library Folder", isPresented: $state.isCreatingFolder) {
            TextField(
                "Folder name",
                text: newFolderNameBinding
            )
                .accessibilityIdentifier("MediaLibrary-NewFolder-name")
            Button("Cancel") {
                recordReachability(.newFolderCancel)
                newFolderName = ""
            }
                .accessibilityIdentifier("MediaLibrary-NewFolder-cancel")
            Button("Create") {
                recordReachability(.newFolderCreate)
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
            TextField(
                "Folder name",
                text: renamedFolderNameBinding
            )
                .accessibilityIdentifier("MediaLibrary-RenameFolder-name")
            Button("Cancel") {
                recordReachability(.renameFolderCancel)
                folderToRename = nil
            }
                .accessibilityIdentifier("MediaLibrary-RenameFolder-cancel")
            Button("Rename") {
                recordReachability(.renameFolderConfirm)
                if let folderToRename {
                    mediaLibrary.rename(folderToRename, to: renamedFolderName)
                }
                folderToRename = nil
            }
            .accessibilityIdentifier("MediaLibrary-RenameFolder-confirm")
        }
        .confirmationDialog(
            Self.removeFolderConfirmation,
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
            isPresented: $state.isBatchRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Selected", role: .destructive) {
                recordReachability(.multiSelection(.confirmDelete))
                mediaLibrary.removeReferences(withIDs: selectedMediaReferenceIDs)
                endMediaReferenceSelection()
            }
            .accessibilityIdentifier("MediaLibrary-MultiSelect-confirmDelete")
            Button("Cancel", role: .cancel) {}
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
            onPrimary: {
                recordReachability(.fileBrowserError(.primary))
                Task { await viewModel.loadFiles() }
            },
            onSecondary: {
                recordReachability(.fileBrowserError(.secondary))
                viewModel.dismissCurrentError()
            }
        )
        .alert(
            "Media Library Error",
            isPresented: Binding(
                get: { mediaLibrary.lastErrorMessage != nil },
                set: { if !$0 { mediaLibrary.lastErrorMessage = nil } }
            )
        ) {
            Button("OK") {
                recordReachability(.mediaLibraryErrorDismiss)
                mediaLibrary.lastErrorMessage = nil
            }
                .accessibilityIdentifier("MediaLibrary-error-dismiss")
        } message: {
            Text(
                mediaLibrary.lastErrorMessage
                    ?? "The original media source is unavailable."
            )
        }
    }

    private var sidebar: some View {
        SourceSidebar(
            items: $state.sourceItems,
            title: "Library & Sources",
            containerIdentifier: "FileBrowsing-MainWindow-sidebar",
            identifierPrefix: "FileBrowsing-SourcesSidebar",
            onSelectSource: { id in
                recordReachability(.sidebarSelect(id))
                select(sourceID: id)
            },
            onAddSource: { type in
                recordReachability(.sidebarAddSource(type))
                presentConnection(for: type)
            },
            onImportFolder: {
                recordReachability(.sidebarAddFolder)
                presentFolderImporter()
            },
            onRefresh: {
                recordReachability(.sidebarRefresh)
                Task { await viewModel.loadFiles() }
            },
            onDeleteSources: deleteSources,
            onReachabilityAction: { action in
                recordReachability(.sourceSidebar(action))
            }
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
                icon: ds.sourceType.sidebarIcon,
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
        Task {
            let result = await viewModel.connectToDataSource(ds)
            if case .failed(let failure) = result,
               viewModel.activeDataSource?.id == ds.id {
                viewModel.lastErrorMessage = failure.sourceConnectionMessage
            }
        }
    }

    private func presentConnection(for sourceType: FileBrowsingDomain.SourceType) {
        switch sourceType.presentation {
        case .serverConnection:
            if sourceConnectionDraftKind != sourceType {
                sourceConnectionDraft = SourceConnectionDraft()
                sourceConnectionDraftKind = sourceType
            }
            presentedSourceConnection = sourceType
        case .fileImporter:
            requestFileImport(.mediaFiles)
        }
    }

    private func presentFolderImporter() {
        requestFileImport(.folder)
    }

    private func requestFileImport(_ kind: FilesScreenFileImportKind) {
        inputs.requestProductEntry(.fileImporter(kind)) { result in
            switch result {
            case .success(let urls):
                switch kind.action(for: urls) {
                case .addFiles(let files):
#if DEBUG
                    let referenceIDsBeforeImport = Set(mediaLibrary.references.map(\.id))
#endif
                    mediaLibrary.addFiles(files)
#if DEBUG
                    SystemImportDeliveryDiagnostics.recordPersistentLibraryDelivery(
                        deliveredURLs: files,
                        newReferences: mediaLibrary.references.filter {
                            referenceIDsBeforeImport.contains($0.id) == false
                        },
                        errorDescription: mediaLibrary.lastErrorMessage
                    )
#endif
                case .addFolder(let folder):
                    Task { await mediaLibrary.addFolder(folder) }
                }
            case .failure(let error):
                mediaLibrary.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func requestPhotosImport() {
        inputs.requestProductEntry(.photos) { result in
            switch result {
            case .success(let urls):
#if DEBUG
                let referenceIDsBeforeImport = Set(mediaLibrary.references.map(\.id))
#endif
                mediaLibrary.addFiles(urls)
#if DEBUG
                SystemImportDeliveryDiagnostics.recordPersistentLibraryDelivery(
                    deliveredURLs: urls,
                    newReferences: mediaLibrary.references.filter {
                        referenceIDsBeforeImport.contains($0.id) == false
                    },
                    errorDescription: mediaLibrary.lastErrorMessage
                )
#endif
            case .failure(let error):
                mediaLibrary.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func dismissSourceConnection() {
        presentedSourceConnection = nil
    }

    private func completeSourceConnection() {
        sourceConnectionDraft.clearAfterSuccessfulConnection()
        sourceConnectionDraftKind = nil
        presentedSourceConnection = nil
    }

    private func connect(
        _ request: SourceConnectionRequest
    ) async -> RemoteConnectionResult {
        recordReachability(
            .sourceConnection(request.kind, .connect)
        )
        do {
            let connection = try FileBrowsingDomain.ConnectionInfo.remote(
                sourceType: request.kind,
                address: request.address,
                username: request.connectsAsGuest ? nil : request.username
            )
            let source = FileBrowsingDomain.DataSource(
                name: sourceName(for: request, connection: connection),
                sourceType: request.kind,
                connectionInfo: connection
            )
            let credential = StorageCredential(
                username: request.connectsAsGuest ? "guest" : request.username,
                password: request.connectsAsGuest ? "" : request.password
            )
            let result = await viewModel.connectToDataSource(
                source,
                credential: credential
            )
            guard result == .connected else {
                return result
            }
            guard viewModel.activeDataSource?.id == source.id else {
                return .connected
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
        } catch is FileBrowsingDomain.ConnectionInfoError {
            return .failed(.invalidAddress)
        } catch let failure as RemoteConnectionFailure {
            return .failed(failure)
        } catch {
            return .failed(.serverUnreachable)
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

    private let mediaLibrarySourceID = "media-library"

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

    private var folderIdentity: String {
        isBrowsingSource
            ? viewModel.currentRemotePath
            : mediaLibrary.currentFolderID?.uuidString ?? "media-library-root"
    }

    @ViewBuilder
    private var filesBody: some View {
        currentFolderContent
            .levelContent(id: folderIdentity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    recordReachability(.navigate(.back))
                    if isBrowsingSource {
                        Task { await viewModel.navigateUp() }
                    } else {
                        mediaLibrary.navigateBack()
                    }
                },
                onForward: {
                    recordReachability(.navigate(.forward))
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
                    text: Binding(
                        get: { viewModel.searchText },
                        set: {
                            recordReachability(.search)
                            viewModel.searchText = $0
                        }
                    ),
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
                    recordReachability(.breadcrumb(.mediaLibrary))
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
                recordReachability(.breadcrumb(.files))
                let stackIndex = segments[position].index
                Task { await viewModel.navigateToBreadcrumb(index: stackIndex) }
            },
            accessibilityIdentifier: "FileBrowsing-Breadcrumb-current"
        )
    }

    private var manageMenu: some View {
        Menu {
            Group {
                Button {
                    performManageAction(.addFiles)
                } label: {
                    Label("Add Files", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("MediaLibrary-Manage-addFiles")
                Button {
                    performManageAction(.addPhotos)
                } label: {
                    Label("Add from Photos", systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("MediaLibrary-Manage-addPhotos")
                Button {
                    performManageAction(.addFolder)
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("MediaLibrary-Manage-addFolder")
                Divider()
                Button {
                    performManageAction(.newFolder)
                } label: {
                    Label("New Library Folder", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("MediaLibrary-Manage-newFolder")
                if !isBrowsingSource {
                    Divider()
                    Button {
                        performManageAction(.selectMultiple)
                    } label: {
                        Label("Select Multiple", systemImage: "checkmark.circle")
                    }
                    .disabled(displayedLibraryReferences.isEmpty)
                    .accessibilityIdentifier("MediaLibrary-Manage-selectMultiple")
                }
            }
            .onAppear { recordReachability(.manageOpened) }
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
                    selectMoveDestination(nil)
                }
                ForEach(mediaLibrary.allFolders) { folder in
                    Button(folder.name) {
                        selectMoveDestination(folder.id)
                    }
                }
            } label: {
                Label("Move To", systemImage: "folder")
            }
            .disabled(selectedMediaReferenceIDs.isEmpty)
            .accessibilityIdentifier("MediaLibrary-MultiSelect-move")

            Button(role: .destructive) {
                recordReachability(.multiSelection(.delete))
                isBatchRemoveConfirmationPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedMediaReferenceIDs.isEmpty)
            .accessibilityIdentifier("MediaLibrary-MultiSelect-delete")

            Button("Done") {
                recordReachability(.multiSelection(.done))
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

    private var grid: some View {
        ScrollView {
            CardGrid {
                if isBrowsingSource {
                    ForEach(viewModel.displayedFolders) { folder in
                        GridCard.folder(
                            title: folder.name,
                            count: nil,
                            accessibilityIdentifier: "FileBrowsing-grid-folder-\(folder.name)",
                            action: {
                                recordReachability(.remoteFolder)
                                Task { await viewModel.navigateToFolder(folder) }
                            }
                        )
                    }
                    ForEach(viewModel.displayedFiles) { file in
                        GridCard.video(
                            title: displayTitle(file),
                            artworkURL: viewModel.artworkURL(for: file),
                            fileSize: fileSizeText(file),
                            duration: durationText(viewModel.fileViewingStates[file.id]?.durationSeconds),
                            watchedProgress: viewModel.fileViewingStates[file.id]?.progress,
                            accessibilityIdentifier: "FileBrowsing-grid-video-\(file.name)",
                            action: {
                                recordReachability(.remoteVideo)
                                viewModel.selectFile(file)
                            }
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
                            action: {
                                recordReachability(.libraryFolder)
                                mediaLibrary.open(folder)
                            }
                        )
                        .contextMenu { libraryFolderActions(folder) }
                    }
                    ForEach(displayedLibraryReferences) { reference in
                        GridCard.video(
                            title: displayTitle(reference),
                            artworkURL: mediaLibrary.artworkURL(for: reference),
                            fileSize: fileSizeText(reference),
                            duration: durationText(
                                mediaLibrary.referenceViewingStates[reference.id]?.durationSeconds
                            ),
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
        }
        .scrollIndicators(.hidden)
#if DEBUG
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { previous, current in
            guard abs(current - previous) >= 1 else { return }
            inputs.onReachabilityEvent(
                .scroll(layout: .grid, offset: Double(current))
            )
        }
#endif
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
#if DEBUG
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { previous, current in
            guard abs(current - previous) >= 1 else { return }
            inputs.onReachabilityEvent(
                .scroll(layout: .list, offset: Double(current))
            )
        }
#endif
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
                            duration: durationText(viewModel.fileViewingStates[file.id]?.durationSeconds),
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
                duration: durationText(mediaLibrary.referenceViewingStates[reference.id]?.durationSeconds),
                contextActions: libraryReferenceContextActions(reference),
                selectionEnabled: mediaReferenceSelectionIsActive,
                isSelected: selectedMediaReferenceIDs.contains(reference.id),
                action: { activateMediaReference(reference) }
            )
        }
    }

    private var sidebarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { uiState.sidebarIsVisible },
            set: {
                recordReachability(.sidebarToggle)
                uiState.sidebarIsVisible = $0
            }
        )
    }

    private var viewModeBinding: Binding<Int> {
        Binding(
            get: { uiState.viewMode == .grid ? 0 : 1 },
            set: {
                recordReachability(.viewMode)
                uiState.viewMode = $0 == 0 ? .grid : .list
            }
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
                recordReachability(.sort)
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
                recordReachability(.sort)
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

    private func durationText(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let totalSeconds = Int(seconds.rounded())
        guard totalSeconds >= 60 else { return "\(totalSeconds) sec" }
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
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
        recordReachability(.libraryVideo)
        inputs.onReachabilityEvent(
            .libraryTap(
                name: reference.name,
                selectionActive: mediaReferenceSelectionIsActive
            )
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

    private func selectMoveDestination(_ folderID: UUID?) {
        recordReachability(.multiSelection(.move))
        moveSelectedMediaReferences(to: folderID)
    }

    private func performManageAction(_ action: FilesScreenManageAction) {
        recordReachability(.manage(action))
        switch action {
        case .addFiles:
            requestFileImport(.mediaFiles)
        case .addPhotos:
            requestPhotosImport()
        case .addFolder:
            presentFolderImporter()
        case .newFolder:
            isCreatingFolder = true
        case .selectMultiple:
            beginMediaReferenceSelection()
        }
    }

#if DEBUG
    private func handleDebugMenuSelection(
        _ request: DebugMenuSelectionRequest
    ) {
        switch (request.host, request.family) {
        case (.files, .manage):
            let actions = FilesScreenManageAction.allCases.filter {
                $0 != .selectMultiple || isBrowsingSource == false
            }
            request.handle(
                host: .files,
                family: .manage,
                items: actions.map { action in
                    DebugMenuSelectionItem(
                        id: action.rawValue,
                        title: action.title,
                        isSelected: false,
                        select: { performManageAction(action) }
                    )
                }
            )
        case (.mediaLibrary, .moveDestination):
            guard mediaReferenceSelectionIsActive else { return }
            let root = DebugMenuSelectionItem(
                id: "root",
                title: "Media Library",
                isSelected: false,
                select: { selectMoveDestination(nil) }
            )
            let folders = mediaLibrary.allFolders.map { folder in
                DebugMenuSelectionItem(
                    id: folder.id.uuidString,
                    title: folder.name,
                    isSelected: false,
                    select: { selectMoveDestination(folder.id) }
                )
            }
            request.handle(
                host: .mediaLibrary,
                family: .moveDestination,
                items: [root] + folders
            )
        case (.mediaLibrary, .referenceMoveDestination):
            let items = displayedLibraryReferences.flatMap { reference in
                let root = DebugMenuSelectionItem(
                    id: "\(reference.id.uuidString):root",
                    title: "\(reference.name) → Media Library",
                    isSelected: false,
                    select: { moveReference(reference, to: nil) }
                )
                let folders = mediaLibrary.allFolders.map { folder in
                    DebugMenuSelectionItem(
                        id: "\(reference.id.uuidString):\(folder.id.uuidString)",
                        title: "\(reference.name) → \(folder.name)",
                        isSelected: false,
                        select: { moveReference(reference, to: folder.id) }
                    )
                }
                return [root] + folders
            }
            request.handle(
                host: .mediaLibrary,
                family: .referenceMoveDestination,
                items: items
            )
        default:
            return
        }
    }
#endif

    private func recordReachability(_ action: FilesScreenReachabilityAction) {
#if DEBUG
        inputs.onReachabilityEvent(.action(action))
#endif
    }

    @ViewBuilder
    private func libraryReferenceActions(_ reference: FileBrowsingDomain.MediaReference) -> some View {
        Menu("Move to", systemImage: "folder") {
            Button("Media Library") { moveReference(reference, to: nil) }
            ForEach(mediaLibrary.allFolders) { folder in
                Button(folder.name) { moveReference(reference, to: folder.id) }
            }
        }
        Button("Remove from Library", systemImage: "trash", role: .destructive) {
            mediaLibrary.remove(reference)
        }
    }

    private func moveReference(
        _ reference: FileBrowsingDomain.MediaReference,
        to folderID: UUID?
    ) {
        recordReachability(.libraryReferenceMove)
        mediaLibrary.move(reference, to: folderID)
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

}
