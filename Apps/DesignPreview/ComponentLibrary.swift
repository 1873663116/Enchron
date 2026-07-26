import DesignSystem
import MediaLibrary
import PlaybackPresentation
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
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-control-navBackForward"
                        )
                    }

                    labeledComponent("View Mode (tap to switch)") {
                        ViewModeCapsuleControl(
                            selection: $viewMode,
                            accessibilityIdentifier: "DesignPreview-ComponentLibrary-control-viewMode"
                        )
                    }
                    labeledComponent("Search") {
                        SearchInputCapsule(
                            text: $searchText,
                            placeholder: "搜索",
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
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .clipShape(Circle())
        .glassBackgroundEffect(in: Circle())
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.automatic)
        .padding((DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Circle())
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
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
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
                    GlassToggle(isOn: true)
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

    // 已看进度变体:同一组卡带不同已观看比例(刚开始 / 过半 / 接近看完)。
    private let watchedVideos: [VideoFixture] = [
        .init(title: "Blade Runner 2049", fileSize: "45.6 GB", duration: "2:29:55", badges: ["HDR"], watchedProgress: 0.18),
        .init(title: "The Martian", fileSize: "31.5 GB", duration: "2:24:11", badges: [], watchedProgress: 0.62),
        .init(title: "Ex Machina", fileSize: "22.7 GB", duration: "2:19:48", badges: ["Dolby Vision"], watchedProgress: 0.95)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("CARDS")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            cardRow("GridCard · folder") {
                ForEach(folders) { folder in
                    GridCard.folder(title: folder.title, count: folder.count)
                }
            }

            cardRow("GridCard · video") {
                ForEach(videos) { video in
                    GridCard.video(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges
                    )
                }
            }

            // 已看进度描边变体(UC-FILE-26):底部 accent 进度条表示已观看比例。
            cardRow("GridCard · video · 已看进度") {
                ForEach(watchedVideos) { video in
                    GridCard.video(
                        title: video.title,
                        fileSize: video.fileSize,
                        duration: video.duration,
                        badges: video.badges,
                        watchedProgress: video.watchedProgress
                    )
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
        var watchedProgress: Double? = nil
        var id: String { title }
    }
}

// MARK: - Small elements

private struct SmallElementsSection: View {
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
            .foregroundStyle(DesignTokens.Surface.supportingText)
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

            labeledComponent("FusedPlayerPanel · transport + progress + 内联设置 · 双击进度条展开时间轴") {
                FusedPlayerPanel()
            }
        }
    }
}

// MARK: - Source Sidebar

struct SourceSidebarSection: View {
    @State private var fullItems = SidebarSourceItem.defaultItems
    @State private var demoCategorySelection = "playback"

    private let demoCategories = [
        CategorySidebarItem(id: "playback", icon: "play.rectangle.fill", title: "Playback"),
        CategorySidebarItem(id: "display", icon: "display", title: "Display"),
        CategorySidebarItem(id: "audio", icon: "speaker.wave.3", title: "Audio"),
        CategorySidebarItem(id: "about", icon: "info.circle", title: "About")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("SIDEBAR")
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary).textCase(.uppercase)

            HStack(alignment: .top, spacing: DesignTokens.Spacing.xl) {
                labeledComponent("SourceSidebar · 交互源列表(重排/滑删/多选/加源,内置存储条)") {
                    SourceSidebar(
                        items: $fullItems,
                        containerIdentifier: "DesignPreview-ComponentLibrary-sourceSidebar",
                        identifierPrefix: "DesignPreview-ComponentLibrary-sourceSidebar"
                    )
                    .frame(height: 420)
                }

                labeledComponent("CategorySidebar · 静态大类分类器(无交互,可选中)") {
                    CategorySidebar(
                        items: demoCategories,
                        selection: $demoCategorySelection,
                        title: "Settings",
                        height: 420,
                        containerIdentifier: "DesignPreview-ComponentLibrary-categorySidebar",
                        identifierPrefix: "DesignPreview-ComponentLibrary-categorySidebar"
                    )
                }
            }

            Text("两个角色 · SourceSidebar(有整套状态机)/ CategorySidebar(纯静态)· 共用 SourceSidebarRow 视觉 / DesignTokens.SourceSidebar")
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
