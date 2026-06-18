import SwiftUI

/// The app's Files browsing screen, assembled from the shared component library
/// and driven by `FileBrowsingViewModel`. Replaces the retired `FileBrowserView`
/// + `ContentGridView`: the same components the DesignPreview `MainWindowPage`
/// reviews, now fed by live (fake-backed) data.
struct FilesScreen: View {
    @Environment(FileBrowsingViewModel.self) private var viewModel

    /// 0 = grid, 1 = list (UC-FILE-34). View-mode is screen-local UI state.
    @State private var viewMode = 0
    @State private var sortKey: SortMenuKey = .name
    @State private var sortOrder: SortMenuOrder = .ascending
    @State private var isMultiSelecting = false
    @State private var sourceItems: [SidebarSourceItem] = []

    private var totalItemCount: Int {
        viewModel.displayedFolders.count + viewModel.displayedFiles.count
    }

    private var isEmpty: Bool {
        viewModel.files.isEmpty && viewModel.folders.isEmpty && !viewModel.isLoading
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
        .onChange(of: viewModel.activeDataSource) { _, _ in syncSourceItems() }
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
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        SourceSidebar(
            items: $sourceItems,
            containerIdentifier: "FileBrowsing-MainWindow-sidebar",
            identifierPrefix: "FileBrowsing-SourcesSidebar",
            onSelectSource: { id in select(sourceID: id) }
        )
    }

    /// Maps the view-model's sources onto the sidebar's value type. "Local Storage"
    /// is always present and non-deletable; saved remote sources follow.
    private func syncSourceItems() {
        var items: [SidebarSourceItem] = [
            SidebarSourceItem(
                id: localSourceID,
                icon: "externaldrive.fill",
                title: "Local Storage",
                isSelected: viewModel.activeDataSource == nil,
                isActiveSource: viewModel.activeDataSource == nil,
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
        if sourceID == localSourceID {
            viewModel.disconnectAndResetToLocal()
            return
        }
        guard let ds = viewModel.savedDataSources.first(where: { $0.id.uuidString == sourceID }) else { return }
        Task { await viewModel.connectToDataSource(ds) }
    }

    private func icon(for type: FileBrowsingDomain.SourceType) -> String {
        switch type {
        case .local: "externaldrive.fill"
        case .smb: "server.rack"
        case .webDAV: "cloud.fill"
        case .photoLibrary: "photo.on.rectangle"
        }
    }

    private let localSourceID = "local-storage"

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
        .accessibilityIdentifier("FileBrowsing-FilesScreen-contentArea")
    }

    @ViewBuilder
    private var filesBody: some View {
        if viewModel.isLoading && viewModel.files.isEmpty && viewModel.folders.isEmpty {
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
            Text("No files here yet")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("FileBrowsing-FilesScreen-emptyState")
        .accessibilityLabel("No files")
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center) {
            NavBackForwardCapsuleControl(
                onBack: { Task { await viewModel.navigateUp() } },
                onForward: { Task { await viewModel.navigateForward() } },
                accessibilityIdentifier: "FileBrowsing-FilesScreen-navBackForward"
            )
            breadcrumb
            Spacer(minLength: DesignTokens.Spacing.xl)
            ViewModeCapsuleControl(
                selection: $viewMode,
                accessibilityIdentifier: "FileBrowsing-FilesScreen-viewMode"
            )
            .disabled(isEmpty)
            SortMenuButton(
                sortKey: $sortKey,
                sortOrder: $sortOrder,
                accessibilityIdentifier: "FileBrowsing-FilesScreen-sort"
            )
            .disabled(isEmpty)
            .onChange(of: sortKey) { _, _ in applySort() }
            .onChange(of: sortOrder) { _, _ in applySort() }
            manageMenu
            SearchInputCapsule(
                text: Binding(get: { viewModel.searchText }, set: { viewModel.searchText = $0 }),
                placeholder: "Search files...",
                accessibilityIdentifier: "FileBrowsing-FilesScreen-search"
            )
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var breadcrumb: some View {
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
            } label: {
                Label("Add Photos", systemImage: "photo.on.rectangle")
            }
            Button {
                Task { await viewModel.useDefaultFolder() }
            } label: {
                Label("Use Documents", systemImage: "folder")
            }
            Button {
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                isMultiSelecting.toggle()
            } label: {
                Label("Select", systemImage: "checkmark.circle")
            }
        } label: {
            GlassCircleIconLabel(
                systemName: "ellipsis",
                accessibilityLabel: "Manage local files",
                iconColor: .secondary
            )
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .accessibilityLabel("Manage local files")
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
                ForEach(viewModel.displayedFolders) { folder in
                    GridCard.folder(
                        title: folder.name,
                        count: 0,
                        accessibilityIdentifier: "FileBrowsing-grid-folder-\(folder.id)"
                    )
                    .onTapGesture { Task { await viewModel.navigateToFolder(folder) } }
                }
                ForEach(viewModel.displayedFiles) { file in
                    GridCard.video(
                        title: displayTitle(file),
                        fileSize: fileSizeText(file),
                        duration: "",
                        accessibilityIdentifier: "FileBrowsing-grid-video-\(file.id)"
                    )
                    .onTapGesture { viewModel.selectFile(file) }
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
                items:
                    viewModel.displayedFolders.map { folder in
                        FileListGroup.Item.folder(
                            id: "folder-\(folder.id)",
                            title: folder.name,
                            itemCount: 0,
                            action: { Task { await viewModel.navigateToFolder(folder) } }
                        )
                    }
                    + viewModel.displayedFiles.map { file in
                        FileListGroup.Item.video(
                            id: "video-\(file.id)",
                            title: displayTitle(file),
                            fileSize: fileSizeText(file),
                            duration: "",
                            action: { viewModel.selectFile(file) }
                        )
                    }
            )
            .frame(maxWidth: gridMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.hidden)
        .transition(.opacity)
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
}
