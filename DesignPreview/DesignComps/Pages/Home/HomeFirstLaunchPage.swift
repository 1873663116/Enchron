import SwiftUI

struct MainWindowPage: View {
    let selectedTab: DesignPreviewTab
    @State private var selectedSettingCategoryID = SettingsCategory.playback.id

    @State private var searchText = ""
    @State private var sourceItems = SidebarSourceItem.defaultItems
    @State private var viewMode = 0
    @State private var sortKey: SortMenuKey = .name
    @State private var sortOrder: SortMenuOrder = .ascending

    private let videos = [
        FileVideo(title: "Interstellar", fileSize: "42.8 GB", duration: "2:28:14", badges: ["MV-HEVC", "HDR"]),
        FileVideo(title: "The Matrix", fileSize: "38.2 GB", duration: "2:43:07", badges: []),
        FileVideo(title: "Dune: Part Two", fileSize: "56.1 GB", duration: "2:44:31", badges: ["HDR10+"]),
        FileVideo(title: "Arrival", fileSize: "28.4 GB", duration: "1:49:22", badges: ["MV-HEVC"]),
        FileVideo(title: "Blade Runner 2049", fileSize: "45.6 GB", duration: "2:29:55", badges: []),
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
                capabilities: .all,
                containerIdentifier: "DesignComps-MainWindowPage-sidebar",
                identifierPrefix: "DesignComps-FilesPage"
            ) {
                storageMeter
            }
        case .settings:
            settingsSidebar
        case .scene:
            EmptyView()
        }
    }

    private var settingsSidebar: some View {
        let shape = DesignTokens.SourceSidebar.shape

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            settingsSidebarSection

            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect(.plate, in: shape, displayMode: .always)
        .padding(.leading, DesignTokens.SourceSidebar.windowInset)
        .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        .accessibilityIdentifier("DesignComps-MainWindowPage-sidebar")
    }

    @ViewBuilder
    private var mainContentArea: some View {
        switch selectedTab {
        case .files:
            filesContentArea
        case .settings:
            settingsContentArea
        case .scene:
            EmptyView()
        }
    }

    private var filesContentArea: some View {
        VStack(spacing: 0) {
            topBar
            itemCountBar
            videoBrowser
        }
        .padding(.leading, contentLeadingPadding)
        .padding(.trailing, contentTrailingPadding)
        .padding(.vertical, DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityIdentifier("DesignComps-FilesPage-contentArea")
    }

    private var contentLeadingPadding: CGFloat {
        viewMode == 0 ? DesignTokens.SourceSidebar.trailingContentGap : DesignTokens.Spacing.xs
    }

    private var contentTrailingPadding: CGFloat {
        viewMode == 0 ? DesignTokens.Spacing.xxl : DesignTokens.Spacing.xs
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
            searchField
        }
        .padding(.bottom, DesignTokens.Spacing.lg)
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
            iconColor: .white,
            accessibilityIdentifier: "DesignComps-FilesPage-viewMode"
        )
    }

    private var toolbarSortButton: some View {
        SortMenuButton(
            sortKey: $sortKey,
            sortOrder: $sortOrder,
            accessibilityIdentifier: "DesignComps-FilesPage-sort"
        )
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
                    VideoCardLarge(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scrollIndicators(.hidden)
        .transition(.opacity)
    }

    private var settingsSidebarSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                sidebarSectionTitle("Settings")
                Spacer(minLength: 0)
                sidebarHeaderTrailingPlaceholder
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

            VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                ForEach(SettingsCategory.allCases) { category in
                    settingsCategoryRow(category)
                }
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
        }
    }

    private var selectedSettingCategory: SettingsCategory {
        SettingsCategory.allCases.first { $0.id == selectedSettingCategoryID } ?? .playback
    }

    private var settingsContentArea: some View {
        GeometryReader { geometry in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    settingsDetailContent(for: selectedSettingCategory)
                        .id(selectedSettingCategory.id)
                        .transition(.opacity)
                }
                .frame(width: settingsDetailColumnWidth(for: geometry.size.width), alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DesignTokens.Spacing.xxxl)
                .animation(DesignTokens.AnimationToken.fadeIn, value: selectedSettingCategoryID)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassBackgroundEffect(.plate, in: DesignTokens.SourceSidebar.shape, displayMode: .always)
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

    private func settingsCategoryRow(_ category: SettingsCategory) -> some View {
        EditableSourceSidebarRow(
            icon: category.icon,
            title: category.title,
            isSelected: selectedSettingCategoryID == category.id,
            isEnabled: true,
            isOnline: false,
            isDeletable: false,
            isSelectionMode: false,
            isChecked: false,
            isAppearing: false,
            isSwipeExpanded: false,
            isDragging: false,
            rowOffset: 0,
            allowsReordering: false,
            onTap: {
                selectedSettingCategoryID = category.id
            },
            onToggleSelection: {},
            onSwipeBegan: {},
            onSwipeExpanded: {},
            onSwipeCollapsed: {},
            onDelete: {},
            onReorderBegan: {},
            onReorderChanged: { _ in },
            onReorderEnded: {}
        )
        .accessibilityIdentifier("DesignComps-SettingsPage-category-\(category.id)")
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.SourceSidebar.sectionTitleFont)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var sidebarHeaderTrailingPlaceholder: some View {
        Color.clear
            .frame(width: DesignTokens.Interactive.compact, height: DesignTokens.Interactive.compact)
            .accessibilityHidden(true)
    }

    private var storageMeter: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("Storage")
                Spacer()
                Text("1.2 TB / 4 TB")
            }
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DesignTokens.Surface.overlay)
                    Capsule()
                        .fill(DesignTokens.Theme.accent)
                        .frame(width: geometry.size.width * 0.3)
                }
            }
            .frame(height: DesignTokens.Spacing.xs)
        }
        .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)
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

    var id: String { title }
}
