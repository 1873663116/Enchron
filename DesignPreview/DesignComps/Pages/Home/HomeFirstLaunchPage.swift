import SwiftUI

struct MainWindowPage: View {
    let selectedTab: DesignPreviewTab
    @State private var selectedSettingCategoryID = SettingsCategory.playback.id

    @State private var searchText = ""
    @State private var sourceItems = SidebarSourceItem.defaultItems
    @State private var isSelectingSidebarItems = false
    @State private var selectedSourceIDs: Set<SidebarSourceItem.ID> = []
    @State private var expandedSourceID: SidebarSourceItem.ID?
    @State private var draggingSourceID: SidebarSourceItem.ID?
    @State private var draggingSourceStartIndex: Int?
    @State private var draggingSourceTargetIndex: Int?
    @State private var sourceDragTranslation: CGFloat = 0
    @State private var appearingSourceIDs: Set<SidebarSourceItem.ID> = []
    @State private var nextDebugSourceIndex = 1
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

    private var mainSidebar: some View {
        let shape = DesignTokens.SourceSidebar.shape

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            sidebarContent

            Spacer(minLength: 0)

            if selectedTab == .files {
                storageMeter
            }
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .glassBackgroundEffect(.plate, in: shape, displayMode: .always)
        .padding(.leading, DesignTokens.SourceSidebar.windowInset)
        .padding(.vertical, DesignTokens.SourceSidebar.windowInset)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                collapseExpandedSource()
            }
        )
        .accessibilityIdentifier("DesignComps-MainWindowPage-sidebar")
    }

    @ViewBuilder
    private var sidebarContent: some View {
        switch selectedTab {
        case .files:
            sourcesSection

            if isSelectingSidebarItems {
                sidebarSelectionActions
            }
        case .settings:
            settingsSidebarSection
        case .scene:
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
        .simultaneousGesture(
            TapGesture().onEnded {
                collapseExpandedSource()
            }
        )
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
            LazyVStack(spacing: 0) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    VideoListRow(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges,
                        showsDivider: index < videos.count - 1
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .enchronTranslucentListContainer()
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
        .padding(.leading, DesignTokens.SourceSidebar.trailingContentGap)
        .padding(.trailing, DesignTokens.SourceSidebar.trailingContentGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("DesignComps-SettingsPage-detailArea")
    }

    private func settingsDetailColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        let safeAvailableWidth = max(availableWidth, 0)
        let idealWidth = min(max(safeAvailableWidth * 0.56, 720), 920)
        return min(idealWidth, safeAvailableWidth)
    }

    private func settingsDetailContent(for category: SettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(category.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)

                Text(category.summary)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.supportingText)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                ForEach(category.sections) { section in
                    SettingsDetailSectionView(section: section)
                }
            }
        }
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

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                sidebarSectionTitle("Sources")
                Spacer(minLength: 0)
                sourceMoreMenu
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

            VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                ForEach(sourceItems) { item in
                    EditableSourceSidebarRow(
                        icon: item.icon,
                        title: item.title,
                        isSelected: item.isSelected,
                        isEnabled: item.isEnabled,
                        isOnline: item.isOnline,
                        isDeletable: item.isDeletable,
                        isSelectionMode: isSelectingSidebarItems,
                        isChecked: selectedSourceIDs.contains(item.id),
                        isAppearing: appearingSourceIDs.contains(item.id),
                        isSwipeExpanded: expandedSourceID == item.id,
                        isDragging: draggingSourceID == item.id,
                        rowOffset: sourceRowOffset(for: item),
                        onToggleSelection: {
                            toggleSourceSelection(item.id)
                        },
                        onSwipeBegan: {
                            collapseExpandedSource(except: item.id)
                        },
                        onSwipeExpanded: {
                            expandSourceSwipe(item.id)
                        },
                        onSwipeCollapsed: {
                            collapseExpandedSource()
                        },
                        onDelete: {
                            deleteSource(item)
                        },
                        onReorderBegan: {
                            beginReorderingSource(item.id)
                        },
                        onReorderChanged: { translation in
                            updateReorderingSource(item.id, translation: translation)
                        },
                        onReorderEnded: {
                            endReorderingSource()
                        }
                    )
                    .zIndex(draggingSourceID == item.id ? 1 : 0)
                    .transition(sourceRowTransition)
                    .accessibilityIdentifier("DesignComps-FilesPage-source-\(item.id)")
                }
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            .animation(DesignTokens.AnimationToken.listMutation, value: sourceItems)
        }
    }

    private var sourceRowTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .scale(scale: 0.94, anchor: .bottom))
                .combined(with: .opacity),
            removal: .scale(scale: 0.92, anchor: .center).combined(with: .opacity)
        )
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

    private var sourceMoreMenu: some View {
        Menu {
            Menu {
                Button {} label: {
                    Label("WebDAV", systemImage: "cloud.fill")
                }
                Button {} label: {
                    Label("SMB", systemImage: "server.rack")
                }
                Button {
                    addDebugSource()
                } label: {
                    Label("Add One", systemImage: "plus.circle")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            Button {} label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Button {
                enterSidebarDeleteSelectionMode()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!hasDeletableSources)
        } label: {
            GlassCircleIconLabel(
                systemName: "ellipsis",
                accessibilityLabel: "More source actions",
                iconColor: .secondary,
                visualSize: DesignTokens.Interactive.compact,
                targetSize: DesignTokens.Interactive.compact,
                font: DesignTokens.Typography.headline,
                accessibilityIdentifier: "DesignComps-FilesPage-sourceMoreLabel"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More source actions")
        .accessibilityIdentifier("DesignComps-FilesPage-sourceMore")
    }

    private var sidebarSelectionActions: some View {
        let selectedCount = selectedSourceIDs.count
        let selectedDeletableCount = selectedSourceIDs.filter(isDeletableSourceID).count

        return HStack(spacing: DesignTokens.Spacing.xs) {
            Text("\(selectedCount)")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
                .frame(minWidth: DesignTokens.Interactive.mini)

            Spacer(minLength: 0)

            if selectedDeletableCount > 0 {
                sidebarSelectionButton(
                    systemName: "trash.fill",
                    accessibilityLabel: "Delete selected sources",
                    tint: .red,
                    action: deleteSelectedSources
                )
            }

            sidebarSelectionButton(
                systemName: "checkmark",
                accessibilityLabel: "Finish selecting",
                action: toggleSidebarSelectionMode
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(minHeight: DesignTokens.Interactive.regular)
        .background(DesignTokens.Surface.elevated, in: DesignTokens.ShapeToken.element)
        .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
        .accessibilityIdentifier("DesignComps-FilesPage-sidebarSelectionActions")
    }

    private func sidebarSelectionButton(
        systemName: String,
        accessibilityLabel: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(tint)
                .frame(width: DesignTokens.Interactive.compact, height: DesignTokens.Interactive.compact)
        }
        .buttonStyle(.plain)
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.automatic)
        .accessibilityLabel(accessibilityLabel)
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

    private func toggleSidebarSelectionMode() {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isSelectingSidebarItems.toggle()
            selectedSourceIDs.removeAll()
        }
    }

    private func enterSidebarDeleteSelectionMode() {
        guard hasDeletableSources else { return }

        collapseExpandedSource()
        withAnimation(DesignTokens.AnimationToken.selection) {
            isSelectingSidebarItems = true
            selectedSourceIDs.removeAll()
        }
    }

    private func toggleSourceSelection(_ id: SidebarSourceItem.ID) {
        guard isDeletableSourceID(id) else { return }

        withAnimation(DesignTokens.AnimationToken.selection) {
            if selectedSourceIDs.contains(id) {
                selectedSourceIDs.remove(id)
            } else {
                selectedSourceIDs.insert(id)
            }
        }
    }

    private func deleteSource(_ item: SidebarSourceItem) {
        guard item.isDeletable else { return }

        collapseExpandedSource()
        withAnimation(DesignTokens.AnimationToken.listMutation) {
            sourceItems.removeAll { $0.id == item.id }
            selectedSourceIDs.remove(item.id)
            appearingSourceIDs.remove(item.id)
        }
    }

    private func deleteSelectedSources() {
        let deletedIDs = selectedSourceIDs.filter(isDeletableSourceID)
        guard !deletedIDs.isEmpty else { return }

        withAnimation(DesignTokens.AnimationToken.listMutation) {
            sourceItems.removeAll { deletedIDs.contains($0.id) }
            selectedSourceIDs.removeAll()
            appearingSourceIDs.subtract(deletedIDs)
            isSelectingSidebarItems = false
        }
    }

    private var hasDeletableSources: Bool {
        sourceItems.contains { $0.isDeletable }
    }

    private func isDeletableSourceID(_ id: SidebarSourceItem.ID) -> Bool {
        sourceItems.first { $0.id == id }?.isDeletable == true
    }

    private func addDebugSource() {
        let debugIndex = nextDebugSourceIndex
        let newSourceID = "debug-source-\(debugIndex)"
        let newSource = SidebarSourceItem(
            id: newSourceID,
            icon: debugIndex.isMultiple(of: 2) ? "server.rack" : "externaldrive.fill",
            title: "Debug Source \(debugIndex)",
            isOnline: debugIndex.isMultiple(of: 2)
        )

        collapseExpandedSource()
        appearingSourceIDs.insert(newSourceID)
        sourceItems.append(newSource)
        nextDebugSourceIndex += 1

        Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(DesignTokens.AnimationToken.listMutation) {
                    appearingSourceIDs.remove(newSourceID)
                }
            }
        }
    }

    private func expandSourceSwipe(_ id: SidebarSourceItem.ID) {
        withAnimation(DesignTokens.AnimationToken.selection) {
            expandedSourceID = id
        }
    }

    private func collapseExpandedSource(except id: SidebarSourceItem.ID? = nil) {
        guard let expandedSourceID, expandedSourceID != id else { return }

        withAnimation(DesignTokens.AnimationToken.selection) {
            self.expandedSourceID = nil
        }
    }

    private func beginReorderingSource(_ id: SidebarSourceItem.ID) {
        guard !isSelectingSidebarItems else { return }

        if expandedSourceID != nil {
            collapseExpandedSource()
            return
        }

        guard draggingSourceID == nil,
              let startIndex = sourceItems.firstIndex(where: { $0.id == id })
        else { return }

        withAnimation(DesignTokens.AnimationToken.selection) {
            draggingSourceID = id
            draggingSourceStartIndex = startIndex
            draggingSourceTargetIndex = startIndex
            sourceDragTranslation = 0
        }
    }

    private func updateReorderingSource(_ id: SidebarSourceItem.ID, translation: CGFloat) {
        guard draggingSourceID == id,
              let startIndex = draggingSourceStartIndex,
              let targetIndex = draggingSourceTargetIndex
        else { return }

        sourceDragTranslation = translation

        let rowStep = DesignTokens.SourceSidebar.rowHeight + DesignTokens.SourceSidebar.rowSpacing
        let relativeTarget = CGFloat(targetIndex - startIndex)
        let switchThreshold = DesignTokens.SourceSidebar.reorderSwitchThreshold
        let returnThreshold = DesignTokens.SourceSidebar.reorderReturnThreshold

        let canMoveDown = targetIndex >= startIndex
            && translation > (relativeTarget + switchThreshold) * rowStep
            && targetIndex < sourceItems.count - 1
        let canMoveUp = targetIndex <= startIndex
            && translation < (relativeTarget - switchThreshold) * rowStep
            && targetIndex > 0
        let canReturnUp = targetIndex > startIndex
            && translation < (relativeTarget - returnThreshold) * rowStep
        let canReturnDown = targetIndex < startIndex
            && translation > (relativeTarget + returnThreshold) * rowStep

        if canMoveDown {
            withAnimation(DesignTokens.AnimationToken.selection) {
                draggingSourceTargetIndex = targetIndex + 1
            }
        } else if canMoveUp {
            withAnimation(DesignTokens.AnimationToken.selection) {
                draggingSourceTargetIndex = targetIndex - 1
            }
        } else if canReturnUp {
            withAnimation(DesignTokens.AnimationToken.selection) {
                draggingSourceTargetIndex = targetIndex - 1
            }
        } else if canReturnDown {
            withAnimation(DesignTokens.AnimationToken.selection) {
                draggingSourceTargetIndex = targetIndex + 1
            }
        }
    }

    private func endReorderingSource() {
        let sourceID = draggingSourceID
        let targetIndex = draggingSourceTargetIndex

        withAnimation(DesignTokens.AnimationToken.selection) {
            if let sourceID,
               let targetIndex,
               let currentIndex = sourceItems.firstIndex(where: { $0.id == sourceID }),
               currentIndex != targetIndex {
                let movedItem = sourceItems.remove(at: currentIndex)
                sourceItems.insert(movedItem, at: targetIndex)
            }

            draggingSourceID = nil
            draggingSourceStartIndex = nil
            draggingSourceTargetIndex = nil
            sourceDragTranslation = 0
        }
    }

    private func sourceRowOffset(for item: SidebarSourceItem) -> CGFloat {
        guard let draggingSourceID,
              let startIndex = draggingSourceStartIndex,
              let targetIndex = draggingSourceTargetIndex,
              let currentIndex = sourceItems.firstIndex(where: { $0.id == item.id })
        else { return 0 }

        let rowStep = DesignTokens.SourceSidebar.rowHeight + DesignTokens.SourceSidebar.rowSpacing

        if draggingSourceID == item.id {
            return sourceDragTranslation
        }

        if targetIndex < startIndex,
           currentIndex >= targetIndex,
           currentIndex < startIndex {
            return rowStep
        }

        if targetIndex > startIndex,
           currentIndex <= targetIndex,
           currentIndex > startIndex {
            return -rowStep
        }

        return 0
    }

}

struct HomeFirstLaunchPage: View {
    var body: some View {
        MainWindowPage(selectedTab: .files)
            .accessibilityIdentifier("DesignComps-HomeFirstLaunchPage")
            .accessibilityLabel("Files page")
    }
}

private struct EditableSourceSidebarRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let isOnline: Bool
    let isDeletable: Bool
    let isSelectionMode: Bool
    let isChecked: Bool
    let isAppearing: Bool
    let isSwipeExpanded: Bool
    let isDragging: Bool
    let rowOffset: CGFloat
    var allowsReordering = true
    var onTap: (() -> Void)?
    let onToggleSelection: () -> Void
    let onSwipeBegan: () -> Void
    let onSwipeExpanded: () -> Void
    let onSwipeCollapsed: () -> Void
    let onDelete: () -> Void
    let onReorderBegan: () -> Void
    let onReorderChanged: (CGFloat) -> Void
    let onReorderEnded: () -> Void

    @State private var swipeDragOffset: CGFloat = 0
    @State private var activeInteraction: RowInteraction?
    @State private var reorderActivationTask: Task<Void, Never>?
    @State private var reorderActivationCueTask: Task<Void, Never>?
    @State private var hoverRestoreTask: Task<Void, Never>?
    @State private var isShowingReorderActivationCue = false
    @State private var isDelayingHoverRestore = false

    private enum RowInteraction {
        case pendingReorder
        case swipe
        case reorder
        case ignored
    }

    var body: some View {
        let rowShape = DesignTokens.SourceSidebar.rowShape
        let offset = clampedSwipeOffset(baseSwipeOffset + swipeDragOffset)
        let deleteRevealWidth = max(-offset, 0)

        ZStack {
            swipeShell(offset: offset, deleteRevealWidth: deleteRevealWidth)
                .offset(y: rowOffset)
                .scaleEffect(rowScale)
                .opacity(isAppearing ? 0 : 1)
                .offset(y: isAppearing ? DesignTokens.SourceSidebar.rowInsertionOffset : 0)
                .contentShape(.hoverEffect, rowShape)
                .hoverEffect(.automatic, isEnabled: isHoverEnabled)
                .gesture(rowInteractionGesture)
                .animation(DesignTokens.AnimationToken.selection, value: isSwipeExpanded)
                .animation(DesignTokens.AnimationToken.selection, value: isDragging)
                .animation(DesignTokens.AnimationToken.selection, value: isShowingReorderActivationCue)
                .animation(DesignTokens.AnimationToken.listMutation, value: isAppearing)
                .animation(isDragging ? nil : DesignTokens.AnimationToken.selection, value: rowOffset)
        }
        .frame(minHeight: DesignTokens.SourceSidebar.rowHeight)
        .onChange(of: isSelectionMode) { _, _ in
            resetSwipeDragOffset()
            resetActiveInteraction()
        }
        .onChange(of: isSwipeExpanded) { _, _ in
            resetSwipeDragOffset()
        }
        .onDisappear {
            resetActiveInteraction()
        }
    }

    private func swipeShell(offset: CGFloat, deleteRevealWidth: CGFloat) -> some View {
        let rowShape = DesignTokens.SourceSidebar.rowShape

        return ZStack {
            deleteActionBackground(revealWidth: deleteRevealWidth)
                .allowsHitTesting(isSwipeExpanded)

            rowSurface
                .offset(x: offset)
        }
        .frame(height: DesignTokens.SourceSidebar.rowHeight)
        .clipShape(rowShape)
        .contentShape(rowShape)
    }

    private var rowSurface: some View {
        let offset = clampedSwipeOffset(baseSwipeOffset + swipeDragOffset)

        return HStack(spacing: DesignTokens.Spacing.xs) {
            if isSelectionMode {
                if isDeletable {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(
                            isChecked
                                ? DesignTokens.Theme.accent
                                : DesignTokens.SourceSidebar.selectionIndicator
                        )
                        .frame(
                            width: DesignTokens.Interactive.compact,
                            height: DesignTokens.SourceSidebar.rowHeight
                        )
                } else {
                    Color.clear
                        .frame(
                            width: DesignTokens.Interactive.compact,
                            height: DesignTokens.SourceSidebar.rowHeight
                        )
                }
            }

            SourceSidebarRow(
                icon: icon,
                title: title,
                isSelected: isSelected || isChecked,
                isEnabled: isEnabled,
                isOnline: isOnline,
                showsSelectionBackground: false
            )
            .frame(maxWidth: .infinity)
        }
        .background(rowSurfaceBackground(offset: offset))
        .contentShape(Rectangle())
    }

    private func rowSurfaceBackground(offset: CGFloat) -> Color {
        if isSelected || isChecked {
            return DesignTokens.Surface.selected
        }

        return offset < -1 ? DesignTokens.Surface.card : .clear
    }

    private var rowScale: CGFloat {
        if isShowingReorderActivationCue {
            return DesignTokens.SourceSidebar.reorderActivationScale
        }

        return isDragging ? DesignTokens.SourceSidebar.reorderLiftScale : 1
    }

    private var isHoverEnabled: Bool {
        activeInteraction == nil && !isDragging && !isSwipeExpanded && !isDelayingHoverRestore
    }

    private var baseSwipeOffset: CGFloat {
        isSwipeExpanded && isDeletable ? -DesignTokens.SourceSidebar.swipeActionWidth : 0
    }

    private func deleteActionBackground(revealWidth: CGFloat) -> some View {
        let actionWidth = DesignTokens.SourceSidebar.swipeActionWidth
        let clampedRevealWidth = min(max(revealWidth, 0), actionWidth)

        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            deleteActionButton
                .frame(width: clampedRevealWidth, alignment: .trailing)
                .clipped()
        }
    }

    private var deleteActionButton: some View {
        Button {
            onSwipeCollapsed()
            onDelete()
        } label: {
            ZStack {
                Color.red.opacity(0.82)
                Image(systemName: "trash.fill")
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(.white)
            }
            .frame(
                width: DesignTokens.SourceSidebar.swipeActionWidth,
                height: DesignTokens.SourceSidebar.rowHeight
            )
            .contentShape(.hoverEffect, Rectangle())
            .hoverEffect(.highlight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete \(title)")
    }

    private var rowInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isSelectionMode else { return }

                let horizontalDistance = abs(value.translation.width)
                let verticalDistance = abs(value.translation.height)
                let movementDistance = max(horizontalDistance, verticalDistance)

                switch activeInteraction {
                case nil:
                    if allowsReordering {
                        beginPendingReorder()
                    }
                    if isDeletable,
                       horizontalDistance > DesignTokens.SourceSidebar.swipeActivationDistance,
                       horizontalDistance > verticalDistance {
                        beginSwipe()
                        updateSwipe(value.translation.width)
                    } else if movementDistance > DesignTokens.SourceSidebar.reorderPressSlop {
                        ignoreCurrentInteraction()
                    }
                case .pendingReorder:
                    if isDeletable,
                       horizontalDistance > DesignTokens.SourceSidebar.swipeActivationDistance,
                       horizontalDistance > verticalDistance {
                        beginSwipe()
                        updateSwipe(value.translation.width)
                    } else if movementDistance > DesignTokens.SourceSidebar.reorderPressSlop {
                        ignoreCurrentInteraction()
                    }
                case .swipe:
                    updateSwipe(value.translation.width)
                case .reorder:
                    onReorderChanged(value.translation.height)
                case .ignored:
                    break
                }
            }
            .onEnded { value in
                if isSelectionMode {
                    if max(abs(value.translation.width), abs(value.translation.height)) <= DesignTokens.SourceSidebar.reorderPressSlop {
                        onToggleSelection()
                    }
                    resetActiveInteraction()
                    return
                }

                finishInteraction(with: value.translation)
            }
    }

    private func clampedSwipeOffset(_ proposedOffset: CGFloat) -> CGFloat {
        min(max(proposedOffset, -DesignTokens.SourceSidebar.swipeActionWidth), 0)
    }

    private func resetSwipeDragOffset() {
        withAnimation(DesignTokens.AnimationToken.selection) {
            swipeDragOffset = 0
        }
    }

    private func beginPendingReorder() {
        guard allowsReordering, activeInteraction == nil else { return }

        activeInteraction = .pendingReorder
        reorderActivationTask = Task {
            try? await Task.sleep(for: .seconds(DesignTokens.SourceSidebar.reorderLongPressDuration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard activeInteraction == .pendingReorder, !isSelectionMode else { return }
                hoverRestoreTask?.cancel()
                hoverRestoreTask = nil
                isDelayingHoverRestore = true
                activeInteraction = .reorder
                startReorderActivationCue()
                onReorderBegan()
            }
        }
    }

    private func beginSwipe() {
        cancelPendingReorder()
        activeInteraction = .swipe
        onSwipeBegan()
    }

    private func updateSwipe(_ horizontalTranslation: CGFloat) {
        let proposedOffset = baseSwipeOffset + horizontalTranslation
        swipeDragOffset = clampedSwipeOffset(proposedOffset) - baseSwipeOffset
    }

    private func finishInteraction(with translation: CGSize) {
        switch activeInteraction {
        case .swipe:
            let proposedOffset = clampedSwipeOffset(baseSwipeOffset + translation.width)
            if proposedOffset < -DesignTokens.SourceSidebar.swipeActionWidth * 0.45 {
                onSwipeExpanded()
            } else {
                onSwipeCollapsed()
            }
            resetSwipeDragOffset()
        case .reorder:
            break
        case .pendingReorder, nil:
            if max(abs(translation.width), abs(translation.height)) <= DesignTokens.SourceSidebar.reorderPressSlop {
                handleTap()
            }
        case .ignored:
            break
        }

        resetActiveInteraction()
    }

    private func cancelPendingReorder() {
        reorderActivationTask?.cancel()
        reorderActivationTask = nil
        if activeInteraction == .pendingReorder {
            activeInteraction = nil
        }
    }

    private func ignoreCurrentInteraction() {
        reorderActivationTask?.cancel()
        reorderActivationTask = nil
        activeInteraction = .ignored
    }

    private func handleTap() {
        if isSelectionMode {
            onToggleSelection()
        } else if isSwipeExpanded {
            onSwipeCollapsed()
        } else {
            onTap?()
        }
    }

    private func startReorderActivationCue() {
        reorderActivationCueTask?.cancel()
        withAnimation(DesignTokens.AnimationToken.selection) {
            isShowingReorderActivationCue = true
        }

        reorderActivationCueTask = Task {
            try? await Task.sleep(for: DesignTokens.SourceSidebar.reorderActivationCueDuration)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard activeInteraction == .reorder else { return }
                withAnimation(DesignTokens.AnimationToken.selection) {
                    isShowingReorderActivationCue = false
                }
            }
        }
    }

    private func resetActiveInteraction() {
        reorderActivationTask?.cancel()
        reorderActivationTask = nil
        reorderActivationCueTask?.cancel()
        reorderActivationCueTask = nil
        isShowingReorderActivationCue = false
        if activeInteraction == .reorder {
            onReorderEnded()
            scheduleHoverRestore()
        } else {
            hoverRestoreTask?.cancel()
            hoverRestoreTask = nil
            isDelayingHoverRestore = false
        }
        activeInteraction = nil
    }

    private func scheduleHoverRestore() {
        hoverRestoreTask?.cancel()
        isDelayingHoverRestore = true
        hoverRestoreTask = Task {
            try? await Task.sleep(for: DesignTokens.SourceSidebar.reorderHoverRestoreDelay)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(DesignTokens.AnimationToken.selection) {
                    isDelayingHoverRestore = false
                }
                hoverRestoreTask = nil
            }
        }
    }
}

private struct SidebarSourceItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isOnline = false
    var isDeletable = true

    static let defaultItems = [
        SidebarSourceItem(
            id: "local-storage",
            icon: "externaldrive.fill",
            title: "Local Storage",
            isOnline: true,
            isDeletable: false
        ),
        SidebarSourceItem(id: "nas-01-smb", icon: "server.rack", title: "NAS-01 (SMB)", isSelected: true, isOnline: true),
        SidebarSourceItem(id: "webdav", icon: "cloud.fill", title: "WebDAV", isEnabled: false)
    ]
}

private struct FileVideo: Identifiable {
    let title: String
    let fileSize: String
    let duration: String
    let badges: [String]

    var id: String { title }
}
