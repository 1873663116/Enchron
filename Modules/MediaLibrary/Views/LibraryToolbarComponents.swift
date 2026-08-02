import DesignSystem
import MediaLibrary
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
        GlassCircleIconMenu(
            systemName: "arrow.up.arrow.down",
            accessibilityLabel: "Sort",
            accessibilityIdentifier: accessibilityIdentifier,
            iconColor: iconColor
        ) {
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
        }
        .accessibilityLabel("Sort")
    }
}
