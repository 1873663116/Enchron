import DesignSystem
import MediaLibrary
import SwiftUI

// MARK: - Source Sidebar
//
// 可复用的来源侧栏组件，从 MainWindowPage 抽取而来，行为与视觉逐字保留。
// 编排能力（重排 / 滑动删除 / 选择模式 / 添加来源）通过 `Capabilities` 逐项开关，
// `viewOnly` 时退化为纯展示的列表。底层行复用 `EditableSourceSidebarRow` 与
// `SourceSidebarRow`，样式与动效全部走 `DesignTokens.SourceSidebar`。

struct SidebarSourceItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isActiveSource = false
    var isDeletable = true

    static let defaultItems = [
        SidebarSourceItem(
            id: "local-storage",
            icon: "externaldrive.fill",
            title: "Local Storage",
            isDeletable: false
        ),
        SidebarSourceItem(id: "nas-01-smb", icon: "server.rack", title: "NAS-01 (SMB)", isSelected: true, isActiveSource: true),
        SidebarSourceItem(id: "webdav", icon: "cloud.fill", title: "WebDAV", isEnabled: false)
    ]
}

struct SourceSidebar: View {
    @Binding var items: [SidebarSourceItem]
    var title: String = "Sources"
    var containerIdentifier: String = "SourceSidebar"
    var identifierPrefix: String = "SourceSidebar"
    /// Invoked when a source row is tapped (not in selection/swipe mode). Optional so
    /// the DesignPreview mock can stay view-only; the app passes it to drive the
    /// view-model's source switching (UC-FILE-16).
    var onSelectSource: ((SidebarSourceItem.ID) -> Void)?
    var onAddSource: ((FileBrowsingDomain.SourceType) -> Void)?
    var onImportFolder: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onDeleteSources: ((Set<SidebarSourceItem.ID>) -> Void)?
    var showsStorageMeter = false

    @State private var isSelectingSidebarItems = false
    @State private var selectedSourceIDs: Set<SidebarSourceItem.ID> = []
    @State private var expandedSourceID: SidebarSourceItem.ID?
    @State private var draggingSourceID: SidebarSourceItem.ID?
    @State private var draggingSourceStartIndex: Int?
    @State private var draggingSourceTargetIndex: Int?
    @State private var sourceDragTranslation: CGFloat = 0
    @State private var appearingSourceIDs: Set<SidebarSourceItem.ID> = []
    @State private var nextDebugSourceIndex = 1

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            sourcesSection

            if isSelectingSidebarItems {
                sidebarSelectionActions
            }

            Spacer(minLength: 0)

            if showsStorageMeter {
                sidebarStorageMeter
            }
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: DesignTokens.SourceSidebar.width)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .enchronSidebarSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerIdentifier)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.SourceSidebar.headerContentGap) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                sidebarSectionTitle(title)
                Spacer(minLength: 0)
                headerTrailingControl
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

            VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                ForEach(items) { item in
                    EditableSourceSidebarRow(
                        icon: item.icon,
                        title: item.title,
                        isSelected: item.isSelected,
                        isEnabled: item.isEnabled,
                        isActiveSource: item.isActiveSource,
                        isDeletable: item.isDeletable,
                        isSelectionMode: isSelectingSidebarItems,
                        isChecked: selectedSourceIDs.contains(item.id),
                        isAppearing: appearingSourceIDs.contains(item.id),
                        isSwipeExpanded: expandedSourceID == item.id,
                        isDragging: draggingSourceID == item.id,
                        rowOffset: sourceRowOffset(for: item),
                        allowsReordering: true,
                        allowsSwipe: true,
                        onTap: {
                            onSelectSource?(item.id)
                        },
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
                    .accessibilityAddTraits(item.isSelected ? .isSelected : [])
                    .accessibilityIdentifier("\(identifierPrefix)-source-\(item.id)")
                }
            }
            .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            .animation(DesignTokens.AnimationToken.listMutation, value: items)
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

    private var headerTrailingControl: some View {
        sourceMoreMenu
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DesignTokens.SourceSidebar.sectionTitleFont)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    // 底部存储条:内置。DesignPreview 是 fake UX,存储数字写死 mock,不开放为参数。
    private var sidebarStorageMeter: some View {
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

    private var sourceMoreMenu: some View {
        GlassCircleIconMenu(
            systemName: "ellipsis",
            accessibilityLabel: "More source actions",
            accessibilityIdentifier: "\(identifierPrefix)-sourceMore",
            iconColor: .secondary
        ) {
            Menu {
                Button {
                    onAddSource?(.local)
                } label: {
                    Label("Files", systemImage: "folder")
                }
                .accessibilityIdentifier("\(identifierPrefix)-addFiles")
                if let onImportFolder {
                    Button(action: onImportFolder) {
                        Label("Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("\(identifierPrefix)-addFolder")
                }
                Button {
                    onAddSource?(.photoLibrary)
                } label: {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("\(identifierPrefix)-addPhotos")
                Button {
                    onAddSource?(.webDAV)
                } label: {
                    Label("WebDAV", systemImage: "cloud.fill")
                }
                .accessibilityIdentifier("\(identifierPrefix)-addWebDAV")
                Button {
                    onAddSource?(.smb)
                } label: {
                    Label("SMB", systemImage: "server.rack")
                }
                .accessibilityIdentifier("\(identifierPrefix)-addSMB")
                if onAddSource == nil {
                    Button {
                        addDebugSource()
                    } label: {
                        Label("Add One", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("\(identifierPrefix)-addDebug")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            Button {
                onRefresh?()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("\(identifierPrefix)-refresh")
            Button {
                enterSidebarDeleteSelectionMode()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!hasDeletableSources)
        }
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
        .accessibilityIdentifier("\(identifierPrefix)-sidebarSelectionActions")
    }

    private func sidebarSelectionButton(
        systemName: String,
        accessibilityLabel: String,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ButtonSymbol(systemName: systemName, tier: .compact)
                .foregroundStyle(tint)
                .frame(width: DesignTokens.Interactive.compact, height: DesignTokens.Interactive.compact)
        }
        .buttonStyle(.plain)
        .enchronHoverContentShape(Circle())
        .enchronHoverEffect(.automatic)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Selection

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

        onDeleteSources?([item.id])
        collapseExpandedSource()
        withAnimation(DesignTokens.AnimationToken.listMutation) {
            items.removeAll { $0.id == item.id }
            selectedSourceIDs.remove(item.id)
            appearingSourceIDs.remove(item.id)
        }
    }

    private func deleteSelectedSources() {
        let deletedIDs = selectedSourceIDs.filter(isDeletableSourceID)
        guard !deletedIDs.isEmpty else { return }

        onDeleteSources?(deletedIDs)
        withAnimation(DesignTokens.AnimationToken.listMutation) {
            items.removeAll { deletedIDs.contains($0.id) }
            selectedSourceIDs.removeAll()
            appearingSourceIDs.subtract(deletedIDs)
            isSelectingSidebarItems = false
        }
    }

    private var hasDeletableSources: Bool {
        items.contains { $0.isDeletable }
    }

    private func isDeletableSourceID(_ id: SidebarSourceItem.ID) -> Bool {
        items.first { $0.id == id }?.isDeletable == true
    }

    private func addDebugSource() {
        let debugIndex = nextDebugSourceIndex
        let newSourceID = "debug-source-\(debugIndex)"
        let newSource = SidebarSourceItem(
            id: newSourceID,
            icon: debugIndex.isMultiple(of: 2) ? "server.rack" : "externaldrive.fill",
            title: "Debug Source \(debugIndex)"
        )

        collapseExpandedSource()
        appearingSourceIDs.insert(newSourceID)
        items.append(newSource)
        nextDebugSourceIndex += 1

        Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }

            _ = await MainActor.run {
                withAnimation(DesignTokens.AnimationToken.listMutation) {
                    appearingSourceIDs.remove(newSourceID)
                }
            }
        }
    }

    // MARK: Swipe & reorder

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
              let startIndex = items.firstIndex(where: { $0.id == id })
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
            && targetIndex < items.count - 1
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
               let currentIndex = items.firstIndex(where: { $0.id == sourceID }),
               currentIndex != targetIndex {
                let movedItem = items.remove(at: currentIndex)
                items.insert(movedItem, at: targetIndex)
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
              let currentIndex = items.firstIndex(where: { $0.id == item.id })
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

// MARK: - Editable row
//
// 逐字保留自 MainWindowPage；唯一新增是可选的 `allowsSwipe`（默认 true，保持原行为），
// 用于让 `SourceSidebar.Capabilities` 关闭滑动删除。Settings 侧栏仍直接复用本行。
