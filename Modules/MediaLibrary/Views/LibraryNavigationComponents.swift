import DesignSystem
import Foundation
import MediaLibrary
import SwiftUI

struct PathBreadcrumbMenu: View {
    let path: [String]
    var onSelectLevel: (Int) -> Void = { _ in }
    var accessibilityIdentifier = "DesignPreview-breadcrumb-current"

    private var currentFolder: String {
        path.last ?? ""
    }

    var body: some View {
        Menu {
            ForEach(Array(path.enumerated()), id: \.offset) { index, _ in
                MenuSelectionRow(
                    pathPrefix(through: index),
                    isSelected: index == path.count - 1,
                    identifier: "\(accessibilityIdentifier)-level-\(index)"
                ) { onSelectLevel(index) }
            }
        } label: {
            Text(currentFolder)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(currentFolder)
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest,
                  request.family == .breadcrumb else {
                return
            }
            let host: DebugMenuSelectionHost
            switch accessibilityIdentifier {
            case "FileBrowsing-Breadcrumb-current": host = .files
            case "MediaLibrary-Breadcrumb-current": host = .mediaLibrary
            default: return
            }
            request.handle(
                host: host,
                family: .breadcrumb,
                items: path.indices.map { index in
                    DebugMenuSelectionItem(
                        id: String(index),
                        title: pathPrefix(through: index),
                        isSelected: index == path.count - 1,
                        select: { onSelectLevel(index) }
                    )
                }
            )
        }
#endif
    }

    private func pathPrefix(through index: Int) -> String {
        path.prefix(index + 1).joined(separator: " / ")
    }
}

struct SearchInputCapsule: View {
    @Binding var text: String
    var placeholder = "Search"
    var accessibilityIdentifier = "DesignPreview-input-search"

    var body: some View {
        GlassSearchField(
            text: $text,
            placeholder: placeholder,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

// MARK: - Category sidebar

/// 分类器条目:图标 + 标题 + 稳定 id。
struct CategorySidebarItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
}

/// 通用静态大类分类器侧栏:在 Settings 页面 / Panel 面板中选一个大类。
/// 天生无重排、无删除、无 footer——就是个可选中的静态列表。行视觉复用纯视觉行 `SourceSidebarRow`。
/// 本件是唯一暴露尺寸(`width`/`height` 成对)的标准件,因 Settings 满宽 vs Panel 紧凑,容器管不了。
struct CategorySidebar: View {
    let items: [CategorySidebarItem]
    @Binding var selection: String
    var title: String = "Categories"
    var width: CGFloat = DesignTokens.SourceSidebar.width
    var height: CGFloat? = nil
    var containerIdentifier: String = "CategorySidebar"
    var identifierPrefix: String = "CategorySidebar"

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.SourceSidebar.headerContentGap) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(title)
                        .font(DesignTokens.SourceSidebar.sectionTitleFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: DesignTokens.Interactive.large,
                               height: DesignTokens.Interactive.large)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

                VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                    ForEach(items) { item in
                        EditableSourceSidebarRow(
                            icon: item.icon,
                            title: item.title,
                            isSelected: selection == item.id,
                            isEnabled: true,
                            isActiveSource: false,
                            isDeletable: false,
                            isSelectionMode: false,
                            isChecked: false,
                            isAppearing: false,
                            isSwipeExpanded: false,
                            isDragging: false,
                            rowOffset: 0,
                            allowsReordering: false,
                            allowsSwipe: false,
                            onTap: { selection = item.id }
                        )
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                        .accessibilityIdentifier("\(identifierPrefix)-category-\(item.id)")
                    }
                }
                .padding(.horizontal, DesignTokens.SourceSidebar.listPaddingH)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, DesignTokens.SourceSidebar.contentPaddingV)
        .frame(width: width)
        .frame(maxHeight: height ?? .infinity, alignment: .topLeading)
        .enchronSidebarSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerIdentifier)
    }
}

/// 播放 deck 的一个菜单条目(字幕 / 音轨 / 倍速 / 剧集任一项)。
/// 选中态与动作由组合阶段(产品层)提供,deck 只负责呈现与打勾。
