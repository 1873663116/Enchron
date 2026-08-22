import SwiftUI

private enum SourceSidebarRowGeometry {
    static let shape = RoundedRectangle(
        cornerRadius: DesignTokens.SourceSidebar.rowCornerRadius,
        style: .continuous
    )
}

// MARK: - Sidebar rows
//
// 侧栏的行，从 MediaLibrary 原地搬来，行为与视觉逐字保留，只放宽了访问级别，
// 让 Emby 侧栏用同一件而不是另抄一份。`EditableSourceSidebarRow` 把选中底色、
// 圆角裁切与 hover 形状统一在同一个矩形上，重排与滑动删除按需关闭。

public extension View {
    /// The surface every browsing sidebar sits on. Part of the window's own surface rather than a
    /// plate floating inside it: a floating plate carries its own glass rim, and its bottom edge sits
    /// above the window's, which leaves a band of page showing between the two. Square, full height,
    /// with a white rim on the trailing edge marking where the sidebar ends and the content area
    /// begins. The leading edge needs no rim: it lands on the window's own boundary.
    func enchronSidebarSurface() -> some View {
        background(.thickMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(DesignTokens.Surface.chromeBorder)
                    .frame(width: DesignTokens.Stroke.regular)
            }
    }
}

public struct SourceSidebarRow: View {
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isActiveSource = false
    var showsSelectionBackground = true

    public init(
        icon: String,
        title: String,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        isActiveSource: Bool = false,
        showsSelectionBackground: Bool = true
    ) {
        self.icon = icon
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isActiveSource = isActiveSource
        self.showsSelectionBackground = showsSelectionBackground
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(isSelected ? DesignTokens.Theme.accent : .secondary)
                .frame(width: DesignTokens.Interactive.mini)

            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isActiveSource {
                Circle()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: DesignTokens.Spacing.xs, height: DesignTokens.Spacing.xs)
            }
        }
        .padding(.horizontal, DesignTokens.SourceSidebar.rowPaddingH)
        .frame(minHeight: DesignTokens.SourceSidebar.rowHeight)
        .background(
            isSelected && showsSelectionBackground ? DesignTokens.Surface.selected : .clear,
            in: SourceSidebarRowGeometry.shape
        )
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(title)
    }
}

public struct EditableSourceSidebarRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let isActiveSource: Bool
    let isDeletable: Bool
    let isSelectionMode: Bool
    let isChecked: Bool
    let isAppearing: Bool
    let isSwipeExpanded: Bool
    let isDragging: Bool
    let rowOffset: CGFloat
    var allowsReordering = true
    var allowsSwipe = true
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

    public init(
        icon: String,
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        isActiveSource: Bool,
        isDeletable: Bool,
        isSelectionMode: Bool,
        isChecked: Bool,
        isAppearing: Bool,
        isSwipeExpanded: Bool,
        isDragging: Bool,
        rowOffset: CGFloat,
        allowsReordering: Bool = true,
        allowsSwipe: Bool = true,
        onTap: (() -> Void)? = nil,
        onToggleSelection: @escaping () -> Void = {},
        onSwipeBegan: @escaping () -> Void = {},
        onSwipeExpanded: @escaping () -> Void = {},
        onSwipeCollapsed: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onReorderBegan: @escaping () -> Void = {},
        onReorderChanged: @escaping (CGFloat) -> Void = { _ in },
        onReorderEnded: @escaping () -> Void = {}
    ) {
        self.icon = icon
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.isActiveSource = isActiveSource
        self.isDeletable = isDeletable
        self.isSelectionMode = isSelectionMode
        self.isChecked = isChecked
        self.isAppearing = isAppearing
        self.isSwipeExpanded = isSwipeExpanded
        self.isDragging = isDragging
        self.rowOffset = rowOffset
        self.allowsReordering = allowsReordering
        self.allowsSwipe = allowsSwipe
        self.onTap = onTap
        self.onToggleSelection = onToggleSelection
        self.onSwipeBegan = onSwipeBegan
        self.onSwipeExpanded = onSwipeExpanded
        self.onSwipeCollapsed = onSwipeCollapsed
        self.onDelete = onDelete
        self.onReorderBegan = onReorderBegan
        self.onReorderChanged = onReorderChanged
        self.onReorderEnded = onReorderEnded
    }

    public var body: some View {
        let rowShape = SourceSidebarRowGeometry.shape
        let offset = clampedSwipeOffset(baseSwipeOffset + swipeDragOffset)
        let deleteRevealWidth = max(-offset, 0)

        ZStack {
            swipeShell(offset: offset, deleteRevealWidth: deleteRevealWidth)
                .offset(y: rowOffset)
                .scaleEffect(rowScale)
                .opacity(isAppearing ? 0 : 1)
                .offset(y: isAppearing ? DesignTokens.SourceSidebar.rowInsertionOffset : 0)
                .enchronHoverContentShape(rowShape)
                .enchronHoverEffect(.automatic, isEnabled: isHoverEnabled)
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
        let rowShape = SourceSidebarRowGeometry.shape

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
                isActiveSource: isActiveSource,
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
                ButtonSymbol(systemName: "trash.fill")
                    .foregroundStyle(.white)
            }
            .frame(
                width: DesignTokens.SourceSidebar.swipeActionWidth,
                height: DesignTokens.SourceSidebar.rowHeight
            )
            .enchronHoverContentShape(Rectangle())
            .enchronHoverEffect(.highlight)
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
                       allowsSwipe,
                       horizontalDistance > DesignTokens.SourceSidebar.swipeActivationDistance,
                       horizontalDistance > verticalDistance {
                        beginSwipe()
                        updateSwipe(value.translation.width)
                    } else if movementDistance > DesignTokens.SourceSidebar.reorderPressSlop {
                        ignoreCurrentInteraction()
                    }
                case .pendingReorder:
                    if isDeletable,
                       allowsSwipe,
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
