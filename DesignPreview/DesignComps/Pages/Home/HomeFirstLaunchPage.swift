import SwiftUI

struct MainWindowPage: View {
    let selectedTab: DesignPreviewTab
    /// 蓝图状态开关:让 Files 内容区在 Canvas 里切到空 / 加载 / 错误态审查。
    /// 默认 `.loaded`,运行时行为不变。
    var filesState: FilesContentState = .loaded
    @State private var selectedSettingCategoryID = SettingsCategory.playback.id

    @State private var searchText = ""
    @State private var sourceItems = SidebarSourceItem.defaultItems
    @State private var viewMode = 0
    @State private var sortKey: SortMenuKey = .name
    @State private var sortOrder: SortMenuOrder = .ascending
    @State private var isMultiSelecting = false
    @State private var showsBrowserError = false

    private let videos = [
        FileVideo(title: "Interstellar", fileSize: "42.8 GB", duration: "2:28:14", badges: ["MV-HEVC", "HDR"], watchedProgress: 0.62),
        FileVideo(title: "The Matrix", fileSize: "38.2 GB", duration: "2:43:07", badges: []),
        FileVideo(title: "Dune: Part Two", fileSize: "56.1 GB", duration: "2:44:31", badges: ["HDR10+"], watchedProgress: 0.18),
        FileVideo(title: "Arrival", fileSize: "28.4 GB", duration: "1:49:22", badges: ["MV-HEVC"]),
        FileVideo(title: "Blade Runner 2049", fileSize: "45.6 GB", duration: "2:29:55", badges: [], watchedProgress: 0.95),
        FileVideo(title: "Ex Machina", fileSize: "22.7 GB", duration: "2:19:48", badges: ["Dolby Vision"]),
        FileVideo(title: "Gravity", fileSize: "18.9 GB", duration: "1:31:07", badges: ["MV-HEVC"]),
        FileVideo(title: "2001: A Space Odyssey", fileSize: "35.1 GB", duration: "2:29:00", badges: []),
        FileVideo(title: "The Martian", fileSize: "31.5 GB", duration: "2:24:11", badges: ["HDR10+"])
    ]

    private var gridMaxWidth: CGFloat {
        DesignTokens.Card.gridMin * 4 + DesignTokens.Card.gridSpacing * 3
    }

    var body: some View {
        HStack(spacing: 0) {
            mainSidebar
            mainContentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 整窗一层玻璃背景:Sidebar(自带玻璃)与内容都坐在它之上;
        // 详情区不再单独叠玻璃,SettingListGroup 直接显示在这层窗口玻璃上。
        .glassBackgroundEffect(.plate, in: DesignTokens.ShapeToken.panel, displayMode: .always)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignComps-MainWindowPage")
        .accessibilityLabel("Main window page")
    }

    @ViewBuilder
    private var mainSidebar: some View {
        switch selectedTab {
        case .files:
            SourceSidebar(
                items: $sourceItems,
                containerIdentifier: "DesignComps-MainWindowPage-sidebar",
                identifierPrefix: "DesignComps-FilesPage"
            )
        case .settings:
            CategorySidebar(
                items: SettingsCategory.allCases.map {
                    CategorySidebarItem(id: $0.id, icon: $0.icon, title: $0.title)
                },
                selection: $selectedSettingCategoryID,
                title: "Settings",
                containerIdentifier: "DesignComps-MainWindowPage-sidebar",
                identifierPrefix: "DesignComps-SettingsPage"
            )
            .padding(.leading, DesignTokens.SourceSidebar.windowInset)
            .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        case .environment:
            EmptyView()
        }
    }

    @ViewBuilder
    private var mainContentArea: some View {
        switch selectedTab {
        case .files:
            filesContentArea
        case .settings:
            settingsContentArea
        case .environment:
            EmptyView()
        }
    }

    private var filesContentArea: some View {
        VStack(spacing: 0) {
            topBar
            if filesState == .loaded {
                itemCountBar
            }
            filesBody
        }
        .padding(.leading, contentLeadingPadding)
        .padding(.trailing, contentTrailingPadding)
        .padding(.vertical, DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityIdentifier("DesignComps-FilesPage-contentArea")
        // 错误对话框(UC-FILE-28):Retry / OK 两按钮,复用 enchron alert 模式。
        .enchronErrorDialog(
            "File Browser Error",
            message: "Couldn't load this location. Check the source connection and try again.",
            primaryTitle: "Retry",
            secondaryTitle: "OK",
            isPresented: $showsBrowserError,
            identifierPrefix: "FileBrowsing-error"
        )
        .onAppear {
            // 错误态(UC-FILE-28)在 Canvas 里直接弹出对话框审查。
            if filesState == .error {
                showsBrowserError = true
            }
        }
    }

    @ViewBuilder
    private var filesBody: some View {
        switch filesState {
        case .loaded:
            videoBrowser
        case .empty:
            filesEmptyState
        case .loading:
            filesLoadingState
        case .error:
            // 错误时内容区留空,对话框承载 Retry / OK。
            Spacer(minLength: 0)
        }
    }

    // 空态(UC-FILE-23):仅 60pt 占位图标 + 一句话,无内容;刷新与多选已在工具栏禁用。
    private var filesEmptyState: some View {
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
        .accessibilityIdentifier("DesignComps-FilesPage-emptyState")
        .accessibilityLabel("No files")
    }

    // 加载态(UC-FILE-24):内容区居中 LoadingSpinner。
    private var filesLoadingState: some View {
        VStack {
            Spacer(minLength: 0)
            LoadingSpinner()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("DesignComps-FilesPage-loadingState")
        .accessibilityLabel("Loading")
    }

    // 网格与列表用同一套内容内缩,保证两种视图模式宽度/padding 一致。
    private var contentLeadingPadding: CGFloat {
        DesignTokens.SourceSidebar.trailingContentGap
    }

    private var contentTrailingPadding: CGFloat {
        DesignTokens.Spacing.xxl
    }

    @ViewBuilder
    private var videoBrowser: some View {
        if viewMode == 0 {
            videoGrid
        } else {
            videoList
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            NavBackForwardCapsuleControl(
                accessibilityIdentifier: "DesignComps-FilesPage-navBackForward"
            )
            breadcrumb
            Spacer(minLength: DesignTokens.Spacing.xl)
            toolbarViewModeControl
            toolbarSortButton
            manageMenu
            searchField
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    // 本地文件管理入口(与侧栏远程源 more 菜单分层):添加 Photos / Use Documents /
    // 新建文件夹 / 多选。复用 SortMenuButton 同款 `Menu { } label: { GlassCircleIconLabel }`
    // 玻璃圆钮模式。视觉阶段动作多为空,多选项切换本地多选态。
    private var manageMenu: some View {
        Menu {
            Button {
            } label: {
                Label("Add Photos", systemImage: "photo.on.rectangle")
            }
            Button {
            } label: {
                Label("Use Documents", systemImage: "folder")
            }
            Button {
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
            Button {
                isMultiSelecting = true
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
        .disabled(filesState == .empty)
        .accessibilityLabel("Manage local files")
        .accessibilityIdentifier("FileBrowsing-Manage-button")
    }

    private var breadcrumb: some View {
        PathBreadcrumbMenu(path: ["Local Storage", "Movies"])
    }

    private var searchField: some View {
        SearchInputCapsule(
            text: $searchText,
            placeholder: "Search files...",
            accessibilityIdentifier: "DesignComps-FilesPage-search"
        )
    }

    private var toolbarViewModeControl: some View {
        ViewModeCapsuleControl(
            selection: $viewMode,
            accessibilityIdentifier: "DesignComps-FilesPage-viewMode"
        )
        // 空态下无内容可切视图(UC-FILE-23)。
        .disabled(filesState == .empty)
    }

    private var toolbarSortButton: some View {
        SortMenuButton(
            sortKey: $sortKey,
            sortOrder: $sortOrder,
            accessibilityIdentifier: "DesignComps-FilesPage-sort"
        )
        // 空态下无内容可排序(UC-FILE-23)。
        .disabled(filesState == .empty)
    }

    private var itemCountBar: some View {
        HStack {
            Spacer()
            Text("\(videos.count) items")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
    }

    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: DesignTokens.Card.gridMin
                        ),
                        spacing: DesignTokens.Card.gridSpacing
                    )
                ],
                alignment: .leading,
                spacing: DesignTokens.Card.gridSpacing
            ) {
                ForEach(videos) { video in
                    GridCard.video(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges,
                        watchedProgress: video.watchedProgress
                    )
                }
            }
            .frame(maxWidth: gridMaxWidth, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var videoList: some View {
        ScrollView {
            FileListGroup(
                items: videos.map { video in
                    .video(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges
                    )
                }
            )
            .frame(maxWidth: gridMaxWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private var selectedSettingCategory: SettingsCategory {
        SettingsCategory.allCases.first { $0.id == selectedSettingCategoryID } ?? .playback
    }

    private var settingsContentArea: some View {
        GeometryReader { geometry in
            ScrollView {
                settingsDetailContent(for: selectedSettingCategory)
                    .frame(width: settingsDetailColumnWidth(for: geometry.size.width), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DesignTokens.Spacing.xxxl)
                    .id(selectedSettingCategory.id)
                    .transition(.opacity)
            }
            .scrollIndicators(.hidden)
            .animation(DesignTokens.AnimationToken.fadeIn, value: selectedSettingCategoryID)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.leading, DesignTokens.SourceSidebar.trailingContentGap)
        .padding(.trailing, DesignTokens.SourceSidebar.windowInset)
        .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        .accessibilityIdentifier("DesignComps-SettingsPage-detailArea")
    }

    private func settingsDetailColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeAvailableWidth = max(availableWidth, 0)
        let idealWidth = min(max(safeAvailableWidth * 0.56, 720), 920)
        return min(idealWidth, safeAvailableWidth)
    }

    private func settingsDetailContent(for category: SettingsCategory) -> some View {
        SettingsDetailContentView(category: category)
    }
}

struct HomeFirstLaunchPage: View {
    var body: some View {
        MainWindowPage(selectedTab: .files)
            .accessibilityIdentifier("DesignComps-HomeFirstLaunchPage")
            .accessibilityLabel("Files page")
    }
}

private struct FileVideo: Identifiable {
    let title: String
    let fileSize: String
    let duration: String
    let badges: [String]
    var watchedProgress: Double? = nil

    var id: String { title }
}

/// Files 内容区的蓝图状态(UC-FILE-23 / 24 / 28)。`.loaded` 是正常态。
enum FilesContentState {
    case loaded
    case empty
    case loading
    case error
}

// === Files 蓝图状态:Canvas 审查入口 ===

#Preview("Files · Empty", windowStyle: .automatic) {
    MainWindowPage(selectedTab: .files, filesState: .empty)
}

#Preview("Files · Loading", windowStyle: .automatic) {
    MainWindowPage(selectedTab: .files, filesState: .loading)
}

#Preview("Files · Error", windowStyle: .automatic) {
    MainWindowPage(selectedTab: .files, filesState: .error)
}
