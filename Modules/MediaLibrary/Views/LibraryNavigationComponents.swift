import DesignSystem
import MediaLibrary
import SwiftUI

struct PathBreadcrumbMenu: View {
    let path: [String]
    var onSelectLevel: (Int) -> Void = { _ in }

    private var currentFolder: String {
        path.last ?? ""
    }

    var body: some View {
        Menu {
            // Picker checkmarks the current level (last) on the trailing edge,
            // natively. Selecting any other level routes through `onSelectLevel`.
            Picker(
                "Path",
                selection: Binding(
                    get: { path.count - 1 },
                    set: { onSelectLevel($0) }
                )
            ) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, _ in
                    Text(pathPrefix(through: index)).tag(index)
                }
            }
            .pickerStyle(.inline)
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
        .accessibilityLabel(currentFolder)
    }

    private func pathPrefix(through index: Int) -> String {
        path.prefix(index + 1).joined(separator: " / ")
    }
}

struct SearchInputCapsule: View {
    @Binding var text: String
    var placeholder = "Search"
    var accessibilityIdentifier = "DesignPreview-input-search"

    // 锁死:宽度恒 Card.gridMin,尺寸归容器管,不暴露。
    private let width: CGFloat = DesignTokens.Card.gridMin

    @State private var pressFeedbackTrigger = 0
    @State private var isInputActive = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.tertiary)

            TextField(
                placeholder,
                text: $text,
                onEditingChanged: handleEditingChanged,
                onCommit: deactivateInput
            )
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .focused($isFocused)
                .enchronLiteralTextInput()
                .enchronHoverEffectDisabled()
                .onTapGesture(perform: activateInput)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: width, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .enchronGlassBackground(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .contentShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Surface.focusBorder.opacity(isInputActive ? 1 : 0),
                    lineWidth: DesignTokens.Stroke.bold
                )
                .animation(DesignTokens.AnimationToken.selection, value: isInputActive)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                activateInput()
            }
        )
        .enchronPressSensoryFeedback(.button, trigger: pressFeedbackTrigger)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                setInputActive(false)
            }
        }
        .onSubmit(deactivateInput)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(placeholder)
    }

    private func activateInput() {
        if !isInputActive {
            pressFeedbackTrigger += 1
        }
        setInputActive(true)
        isFocused = true
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        if isEditing {
            setInputActive(true)
        } else {
            deactivateInput()
        }
    }

    private func deactivateInput() {
        setInputActive(false)
        isFocused = false
    }

    private func setInputActive(_ active: Bool) {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isInputActive = active
        }
    }
}

struct SourceSidebarRow: View {
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isActiveSource = false
    var showsSelectionBackground = true

    var body: some View {
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
            in: DesignTokens.SourceSidebar.rowShape
        )
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(title)
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
        let shape = DesignTokens.SourceSidebar.shape

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(title)
                        .font(DesignTokens.SourceSidebar.sectionTitleFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: DesignTokens.Interactive.compact,
                               height: DesignTokens.Interactive.compact)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

                VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                    ForEach(items) { item in
                        SourceSidebarRow(
                            icon: item.icon,
                            title: item.title,
                            isSelected: selection == item.id
                        )
                        .contentShape(DesignTokens.SourceSidebar.rowShape)
                        .onTapGesture { selection = item.id }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.title)
                        .accessibilityAddTraits(selection == item.id ? [.isButton, .isSelected] : .isButton)
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
        .enchronPlateGlassBackground(in: shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerIdentifier)
    }
}

/// 播放 deck 的一个菜单条目(字幕 / 音轨 / 倍速 / 剧集任一项)。
/// 选中态与动作由组合阶段(产品层)提供,deck 只负责呈现与打勾。
