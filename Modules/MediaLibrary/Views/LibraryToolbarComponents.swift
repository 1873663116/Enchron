import SwiftUI

enum SortMenuKey {
    case name
    case modifiedDate
    case size
}

enum SortMenuOrder {
    case ascending
    case descending
}

struct SortMenuButton: View {
    @Binding var sortKey: SortMenuKey
    @Binding var sortOrder: SortMenuOrder
    var accessibilityIdentifier: String = "DesignPreview-menu-sort"

    // 锁死:图标恒 .secondary,不暴露。
    private let iconColor: Color = .secondary

    var body: some View {
        Menu {
            // Picker renders the selected row with a system checkmark on the
            // trailing edge — the native menu idiom. A hand-rolled
            // `Label(systemImage: "checkmark")` forced the mark to the leading
            // edge, shoving the title right.
            Picker("Sort By", selection: $sortKey) {
                Text("Name").tag(SortMenuKey.name)
                Text("Date Modified").tag(SortMenuKey.modifiedDate)
                Text("Size").tag(SortMenuKey.size)
            }
            .pickerStyle(.inline)

            Picker("Order", selection: $sortOrder) {
                Text("Ascending").tag(SortMenuOrder.ascending)
                Text("Descending").tag(SortMenuOrder.descending)
            }
        } label: {
            GlassCircleIconLabel(
                systemName: "arrow.up.arrow.down",
                accessibilityLabel: "Sort",
                iconColor: iconColor
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct GlassCapsuleIconLabelButton: View {
    let title: String
    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void = {}
    var accessibilityIdentifier: String?

    // 锁死:图标恒白、最小宽度恒 regular*2,不暴露。
    private let iconColor: Color = .white
    private let minWidth: CGFloat = DesignTokens.Interactive.regular * 2

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(iconColor)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minWidth: minWidth, minHeight: DesignTokens.Interactive.regular)
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.control))
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Capsule())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-button-\(title)")
    }
}

