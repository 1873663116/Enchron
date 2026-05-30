import SwiftUI

// MARK: - Bare button style (no built-in hover, no chrome)

/// Custom ButtonStyle that disables the system's default hover effect.
/// Unlike `.plain`, a custom ButtonStyle does not add automatic hover highlight.
private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

// MARK: - Component Library
// Every component isolated with labels showing token/variant info.

struct ComponentLibraryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                PlayerSection()
                CircleButtonsSection()
                ToggleSection()
                LoadingSection()
                CardsSection()
                RowsSection()
                ContainersSection()
                InteractiveMenuSection()
                SmallElementsSection()
                DestructiveConfirmationSection()
            }
            .padding(DesignTokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .navigationTitle("Components")
    }
}

// MARK: - Circle Buttons (interactive: tap to select/deselect)

private struct CircleButtonsSection: View {
    @State private var selected: String?
    @State private var viewMode = 0
    @State private var sortKey: SortMenuKey = .name
    @State private var sortOrder: SortMenuOrder = .ascending
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CIRCLE BUTTONS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                HStack(spacing: DesignTokens.Spacing.xl) {
                    labeledComponent("Back") {
                        interactiveCircle("chevron.left", id: "back")
                    }
                    labeledComponent("Forward") {
                        interactiveCircle("chevron.right", id: "forward")
                    }
                    labeledComponent("Sort") {
                        sortMenuButton
                    }
                    labeledComponent("Source Menu") {
                        sourceMenuButton
                    }
                    labeledComponent("Expand") {
                        GlassCapsuleIconLabelButton(
                            title: "Expand",
                            systemName: "arrow.up.left.and.arrow.down.right",
                            accessibilityLabel: "Expand",
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-button-expand"
                        )
                    }
                    labeledComponent("Expand Icon") {
                        GlassCircleIconButton(
                            systemName: "arrow.up.left.and.arrow.down.right",
                            accessibilityLabel: "Expand",
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-button-expand-icon"
                        )
                    }
                    labeledComponent("More") {
                        GlassCircleIconButton(
                            systemName: "ellipsis",
                            accessibilityLabel: "More",
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-button-more"
                        )
                    }
                }

                HStack(spacing: DesignTokens.Spacing.xl) {
                    labeledComponent("Nav Back/Forward") {
                        NavBackForwardCapsuleControl(
                            iconColor: .white,
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-control-navBackForward"
                        )
                    }

                    labeledComponent("View Mode (tap to switch)") {
                        ViewModeCapsuleControl(
                            selection: $viewMode,
                            iconColor: .white,
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-control-viewMode"
                        )
                    }
                    labeledComponent("Search") {
                        SearchInputCapsule(
                            text: $searchText,
                            placeholder: "搜索",
                            width: DesignTokens.Card.gridMin + DesignTokens.Spacing.xxxl + DesignTokens.Spacing.md,
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-input-search"
                        )
                    }
                }
            }

            Text("44pt glass circle · hover + selected · tap to toggle")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func interactiveCircle(_ icon: String, id: String) -> some View {
        let isSelected = selected == id
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                selected = isSelected ? nil : id
            }
        } label: {
            Image(systemName: icon)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Circle())
        .glassBackgroundEffect(in: Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.automatic)
        .padding((DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Circle())
        .enchronPressFeedback(.icon)
    }

    @ViewBuilder
    private var sortMenuButton: some View {
        SortMenuButton(
            sortKey: $sortKey,
            sortOrder: $sortOrder,
            accessibilityIdentifier: "DesignPreview-ComponentLibrary-menu-sort"
        )
    }

    private var sourceMenuButton: some View {
        Menu {
            Section("Local") {
                Button("Choose Folder...") {}
                Button("Import Video...") {}
                Button("Photo Library...") {}
                Button("Use App Documents") {}
            }
            Section("Remote") {
                Button("Add WebDAV Server...") {}
                Button("Add SMB Server...") {}
                Menu("Reconnect") {
                    Button("SMB://NAS") {}
                    Button("WebDAV://Drive") {}
                }
            }
            Button("Disconnect", role: .destructive) {}
        } label: {
            Image(systemName: "ellipsis")
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle())
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.automatic)
                .contentShape(Circle())
                .enchronPressFeedback(.icon)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-ComponentLibrary-menu-source")
        .accessibilityLabel("Source Menu")
    }

}


// MARK: - Loading spinner

private struct LoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("LOADING")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Small (36pt)") {
                    LoadingSpinner(size: 36)
                }
                labeledComponent("Default (56pt)") {
                    LoadingSpinner()
                }
                labeledComponent("Large (80pt)") {
                    LoadingSpinner(size: 80)
                }
            }

            Text("Glass circle · #39C5BB glow · arc stretch")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Toggle (interactive, glass material)

private struct ToggleSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("TOGGLE")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Tap to toggle") {
                    MockToggle(isOn: true)
                }
            }

            Text("50×30pt · glass material · tap to switch")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Cards

private struct CardsSection: View {
    private let folders: [FolderFixture] = [
        .init(title: "Movies", count: 24),
        .init(title: "Spatial", count: 12),
        .init(title: "Downloads", count: 8),
        .init(title: "Archive", count: 36)
    ]

    private let videos: [VideoFixture] = [
        .init(title: "Interstellar", fileSize: "8.2 GB", duration: "2:49:00", badges: ["HDR10+"]),
        .init(title: "Dune: Part Two", fileSize: "56.1 GB", duration: "2:44:31", badges: ["HDR"]),
        .init(title: "Arrival", fileSize: "28.4 GB", duration: "1:49:22", badges: ["MV-HEVC"]),
        .init(title: "Gravity", fileSize: "18.9 GB", duration: "1:31:07", badges: [])
    ]

    private let scenes: [SceneFixture] = [
        .init(icon: "rectangle.on.rectangle", title: "Window", isSelected: true),
        .init(icon: "sparkles.tv", title: "Cinema", isSelected: false),
        .init(icon: "mountain.2", title: "Space", isSelected: false),
        .init(icon: "moon.stars", title: "Night", isSelected: false)
    ]

    private var componentCardWidth: CGFloat {
        DesignTokens.Card.gridMin - DesignTokens.Spacing.md
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CARDS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            cardRow("FolderCard") {
                ForEach(folders) { folder in
                    FolderCard(title: folder.title, count: folder.count, width: componentCardWidth)
                }
            }

            cardRow("VideoCardLarge") {
                ForEach(videos) { video in
                    VideoCardLarge(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges,
                        width: componentCardWidth
                    )
                }
            }

            cardRow("SceneCardMedium") {
                ForEach(scenes) { scene in
                    SceneCardMedium(icon: scene.icon, title: scene.title, isSelected: scene.isSelected)
                        .frame(width: componentCardWidth)
                }
            }
        }
    }

    private func cardRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            HStack(alignment: .top, spacing: DesignTokens.Card.gridSpacing) {
                content()
            }
        }
    }

    private struct FolderFixture: Identifiable {
        let title: String
        let count: Int
        var id: String { title }
    }

    private struct VideoFixture: Identifiable {
        let title: String
        let fileSize: String
        let duration: String
        let badges: [String]
        var id: String { title }
    }

    private struct SceneFixture: Identifiable {
        let icon: String
        let title: String
        let isSelected: Bool
        var id: String { title }
    }
}

// MARK: - Rows

private struct RowsSection: View {
    @State private var selectedAudioTrack = "English 5.1"
    @State private var selectedCaptions = "Off"

    private let audioTracks = ["English 5.1", "Japanese 2.0", "Commentary"]
    private let captionTracks = ["Off", "English (CC)", "中文简体"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("ROWS / LIST ITEMS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    FileListRow(icon: "folder", title: "Movies", metadata: "24 items")
                    FileListRow(icon: "film", title: "Blade Runner 2049", metadata: "4K · 5.3 GB")
                }
                .frame(maxWidth: 600)

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    NativeSelectionMenuRow(
                        title: "Audio Track",
                        selection: $selectedAudioTrack,
                        options: audioTracks
                    )
                    NativeSelectionMenuRow(
                        title: "Captions",
                        selection: $selectedCaptions,
                        options: captionTracks
                    )
                }
                .frame(width: DesignTokens.Menu.panelWidth)
            }

            Text("element(24) + highlight hover · minHeight 60pt")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct NativeSelectionMenuRow: View {
    let title: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Label(option, systemImage: option == selection ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(.body)
                    Text(selection)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: DesignTokens.Spacing.sm)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.Interactive.rowHeight)
            .enchronGlassMenuItem()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("DesignPreview-ComponentLibrary-menu-\(title)")
        .accessibilityLabel(title)
    }
}

// MARK: - Containers

private struct ContainersSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CONTAINERS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                // Menu container
                labeledComponent("MenuContainer\ncard(32) · 8pt padding → element(24)") {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        MenuItemRow(title: "Option A", isExpanded: false)
                        MenuItemRow(title: "Option B", isExpanded: false)
                        MenuItemRow(title: "Option C", isExpanded: false)
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.panelWidth)
                    .enchronGlassMenu()
                }

                // Source menu (with disconnect)
                labeledComponent("SourceMenu\n(red destructive action)") {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        MenuItemRow(title: "Connect New Source", isExpanded: false)
                        HStack {
                            Text("Disconnect").font(.body).foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .frame(minHeight: DesignTokens.Interactive.rowHeight)
                        .enchronGlassMenuItem()
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.panelWidth)
                    .enchronGlassMenu()
                }

                // Large panel
                labeledComponent("LargePanel\npanel(40) regularMaterial") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("Settings Panel").font(DesignTokens.Typography.headline)
                        Text("Content with regularMaterial background.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    .padding(DesignTokens.Spacing.lg)
                    .frame(width: 280)
                    .enchronGlassPanel()
                }
            }
        }
    }
}

// MARK: - Interactive Menu + Submenu

private struct InteractiveMenuSection: View {
    @State private var expandedItem: String?
    private let menuItems = ["Audio Track", "Subtitle", "Speed"]
    private let submenuData: [String: [String]] = [
        "Audio Track": ["English 5.1", "Japanese 2.0", "Commentary"],
        "Subtitle": ["English (CC)", "中文简体", "Off"],
        "Speed": ["0.5×", "1.0×", "1.5×", "2.0×"],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("MENU + SUBMENU")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    ForEach(menuItems, id: \.self) { item in
                        Button {
                            withAnimation(DesignTokens.AnimationToken.menuPopup) {
                                expandedItem = expandedItem == item ? nil : item
                            }
                        } label: {
                            MenuItemRow(title: item, isExpanded: expandedItem == item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DesignTokens.Menu.glassPadding)
                .frame(width: DesignTokens.Menu.panelWidth)
                .enchronGlassMenu()

                if let selected = expandedItem, let options = submenuData[selected] {
                    VStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                            SubMenuItemRow(title: option, isChecked: idx == 0)
                        }
                    }
                    .padding(DesignTokens.Menu.glassPadding)
                    .frame(width: DesignTokens.Menu.submenuWidth)
                    .enchronGlassMenu()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }

            Text("点击条目展开子菜单 · menuPopup 动效 · glass material")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Small elements

private struct SmallElementsSection: View {
    @State private var selectedFilter = "All"
    private let filters = ["All", "Movies", "TV Shows", "Concerts"]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("SMALL ELEMENTS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Badges · Capsule ultraThin") {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        badgeItem("HDR10+")
                        badgeItem("MV-HEVC")
                        badgeItem("Atmos")
                    }
                }

                labeledComponent("FilterPills · 点击切换") {
                    FilterPillBar(filters: filters, selection: $selectedFilter)
                }

                labeledComponent("Breadcrumb") {
                    MockBreadcrumb()
                }

                labeledComponent("PathBreadcrumbMenu") {
                    PathBreadcrumbMenu(path: ["Local Storage", "Movies"])
                }
            }
        }
    }

    @ViewBuilder
    private func badgeItem(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .enchronGlassBadge()
    }
}

// MARK: - Destructive Confirmation (system alert · ButtonRole.destructive)

private struct DestructiveConfirmationSection: View {
    @State private var isPresented = false
    @State private var didConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("DESTRUCTIVE CONFIRMATION")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            labeledComponent("点击触发系统确认 alert") {
                Button("Remove Source") { isPresented = true }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("DesignPreview-trigger-destructiveConfirmation")
            }

            Text(didConfirm
                 ? "已确认移除（示意）"
                 : "系统 alert · 标题+描述 · Cancel 固定 · Confirm 走 ButtonRole.destructive 自动红")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .enchronDestructiveConfirmation(
            "移除来源？",
            message: "移除后该来源下的浏览记录将不再显示。此操作无法撤销。",
            confirmTitle: "移除",
            isPresented: $isPresented,
            onConfirm: { didConfirm = true }
        )
    }
}

// MARK: - Player components

private struct PlayerSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("PLAYER CONTROLS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            labeledComponent("PlayerControlDeck · progress + transport · double-tap track to expand timeline") {
                PlayerControlDeck()
            }
        }
    }
}

// MARK: - Source Sidebar

struct SourceSidebarSection: View {
    @State private var fullItems = SidebarSourceItem.defaultItems
    @State private var plainItems = SidebarSourceItem.defaultItems

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("SIDEBAR")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                labeledComponent("Full · reorder + swipe + select + add") {
                    SourceSidebar(
                        items: $fullItems,
                        capabilities: .all,
                        containerIdentifier: "DesignPreview-ComponentLibrary-sourceSidebar-full",
                        identifierPrefix: "DesignPreview-ComponentLibrary-sourceSidebar-full"
                    )
                    .frame(height: 420)
                }

                labeledComponent("View only · 纯展示列表") {
                    SourceSidebar(
                        items: $plainItems,
                        capabilities: .viewOnly,
                        showsStatusIndicators: false,
                        containerIdentifier: "DesignPreview-ComponentLibrary-sourceSidebar-plain",
                        identifierPrefix: "DesignPreview-ComponentLibrary-sourceSidebar-plain"
                    )
                    .frame(height: 420)
                }
            }

            Text("SourceSidebar · Capabilities 可逐项开关 · 复用 SourceSidebarRow / DesignTokens.SourceSidebar")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Helper

@ViewBuilder
private func labeledComponent<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: DesignTokens.Spacing.xs) {
        content()
        Text(label)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }
}


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

// 顶层类型：Swift 不允许泛型类型（SourceSidebar<Footer>）的嵌套类型持有 static stored property，
// 因此 Capabilities 提为顶层 OptionSet。
struct SourceSidebarCapabilities: OptionSet {
    let rawValue: Int

    /// 长按拖动重排行序
    static let reorder = SourceSidebarCapabilities(rawValue: 1 << 0)
    /// 横向滑动显露删除
    static let swipeDelete = SourceSidebarCapabilities(rawValue: 1 << 1)
    /// 多选模式（勾选 + 批量删除）
    static let selection = SourceSidebarCapabilities(rawValue: 1 << 2)
    /// 头部菜单中的「添加来源」入口
    static let addSource = SourceSidebarCapabilities(rawValue: 1 << 3)

    static let all: SourceSidebarCapabilities = [.reorder, .swipeDelete, .selection, .addSource]
    static let viewOnly: SourceSidebarCapabilities = []
}

struct SourceSidebar<Footer: View>: View {
    @Binding var items: [SidebarSourceItem]
    var title: String = "Sources"
    var capabilities: SourceSidebarCapabilities = .all
    var showsStatusIndicators = true
    var containerIdentifier: String = "SourceSidebar"
    var identifierPrefix: String = "SourceSidebar"
    @ViewBuilder var footer: () -> Footer

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
        let shape = DesignTokens.SourceSidebar.shape

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            sourcesSection

            if capabilities.contains(.selection) && isSelectingSidebarItems {
                sidebarSelectionActions
            }

            Spacer(minLength: 0)

            footer()
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
        .accessibilityIdentifier(containerIdentifier)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
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
                        isOnline: showsStatusIndicators && item.isOnline,
                        isDeletable: item.isDeletable,
                        isSelectionMode: isSelectingSidebarItems,
                        isChecked: selectedSourceIDs.contains(item.id),
                        isAppearing: appearingSourceIDs.contains(item.id),
                        isSwipeExpanded: expandedSourceID == item.id,
                        isDragging: draggingSourceID == item.id,
                        rowOffset: sourceRowOffset(for: item),
                        allowsReordering: capabilities.contains(.reorder),
                        allowsSwipe: capabilities.contains(.swipeDelete),
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

    @ViewBuilder
    private var headerTrailingControl: some View {
        if capabilities.contains(.addSource) || capabilities.contains(.selection) {
            sourceMoreMenu
        } else {
            sidebarHeaderTrailingPlaceholder
        }
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
            if capabilities.contains(.addSource) {
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
            }
            Button {} label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            if capabilities.contains(.selection) {
                Button {
                    enterSidebarDeleteSelectionMode()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!hasDeletableSources)
            }
        } label: {
            GlassCircleIconLabel(
                systemName: "ellipsis",
                accessibilityLabel: "More source actions",
                iconColor: .secondary,
                visualSize: DesignTokens.Interactive.compact,
                targetSize: DesignTokens.Interactive.compact,
                font: DesignTokens.Typography.headline,
                accessibilityIdentifier: "\(identifierPrefix)-sourceMoreLabel"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More source actions")
        .accessibilityIdentifier("\(identifierPrefix)-sourceMore")
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
            title: "Debug Source \(debugIndex)",
            isOnline: debugIndex.isMultiple(of: 2)
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

extension SourceSidebar where Footer == EmptyView {
    init(
        items: Binding<[SidebarSourceItem]>,
        title: String = "Sources",
        capabilities: SourceSidebarCapabilities = .all,
        showsStatusIndicators: Bool = true,
        containerIdentifier: String = "SourceSidebar",
        identifierPrefix: String = "SourceSidebar"
    ) {
        self.init(
            items: items,
            title: title,
            capabilities: capabilities,
            showsStatusIndicators: showsStatusIndicators,
            containerIdentifier: containerIdentifier,
            identifierPrefix: identifierPrefix
        ) {
            EmptyView()
        }
    }
}

// MARK: - Editable row
//
// 逐字保留自 MainWindowPage；唯一新增是可选的 `allowsSwipe`（默认 true，保持原行为），
// 用于让 `SourceSidebar.Capabilities` 关闭滑动删除。Settings 侧栏仍直接复用本行。

struct EditableSourceSidebarRow: View {
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
