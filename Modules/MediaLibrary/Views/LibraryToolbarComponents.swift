import DesignSystem
import Foundation
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

    private func keyRow(_ title: String, _ key: SortMenuKey, _ id: String) -> some View {
        MenuSelectionRow(
            title,
            isSelected: sortKey == key,
            identifier: "\(accessibilityIdentifier)-\(id)"
        ) { sortKey = key }
    }

    private func orderRow(_ title: String, _ order: SortMenuOrder, _ id: String) -> some View {
        MenuSelectionRow(
            title,
            isSelected: sortOrder == order,
            identifier: "\(accessibilityIdentifier)-\(id)"
        ) { sortOrder = order }
    }

    var body: some View {
        GlassCircleIconMenu(
            systemName: "arrow.up.arrow.down",
            accessibilityLabel: "Sort",
            accessibilityIdentifier: accessibilityIdentifier,
            iconColor: iconColor
        ) {
            // A Section swallows the identifiers of every row inside it, so the
            // two groups are separated by a divider instead. Measured on device.
            keyRow("Name", .name, "name")
            keyRow("Date Modified", .modifiedDate, "modifiedDate")
            keyRow("Size", .size, "size")

            Divider()

            orderRow("Ascending", .ascending, "ascending")
            orderRow("Descending", .descending, "descending")
        }
        .accessibilityLabel("Sort")
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard accessibilityIdentifier == "FileBrowsing-FilesScreen-sort",
                  let request = notification.object as? DebugMenuSelectionRequest else {
                return
            }
            switch request.family {
            case .sortKey:
                request.handle(
                    host: .files,
                    family: .sortKey,
                    items: [
                        DebugMenuSelectionItem(
                            id: "name",
                            title: "Name",
                            isSelected: sortKey == .name,
                            select: { sortKey = .name }
                        ),
                        DebugMenuSelectionItem(
                            id: "modifiedDate",
                            title: "Date Modified",
                            isSelected: sortKey == .modifiedDate,
                            select: { sortKey = .modifiedDate }
                        ),
                        DebugMenuSelectionItem(
                            id: "size",
                            title: "Size",
                            isSelected: sortKey == .size,
                            select: { sortKey = .size }
                        ),
                    ]
                )
            case .sortOrder:
                request.handle(
                    host: .files,
                    family: .sortOrder,
                    items: [
                        DebugMenuSelectionItem(
                            id: "ascending",
                            title: "Ascending",
                            isSelected: sortOrder == .ascending,
                            select: { sortOrder = .ascending }
                        ),
                        DebugMenuSelectionItem(
                            id: "descending",
                            title: "Descending",
                            isSelected: sortOrder == .descending,
                            select: { sortOrder = .descending }
                        ),
                    ]
                )
            default:
                return
            }
        }
#endif
    }
}
