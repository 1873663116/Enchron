import DesignSystem
import Foundation
import MediaLibrary
import SwiftUI

public enum SortMenuKey: Hashable {
    case name
    case modifiedDate
    case size
}

public enum SortMenuOrder {
    case ascending
    case descending
}

public struct SortMenuButton: View {
    @Binding var sortKey: SortMenuKey
    @Binding var sortOrder: SortMenuOrder
    var unavailableKeys: Set<SortMenuKey> = []
    var accessibilityIdentifier: String = "DesignSystem-menu-sort"

    private let iconColor: Color = .secondary

    private func keyRow(_ title: String, _ key: SortMenuKey, _ id: String) -> some View {
        MenuSelectionRow(
            title,
            isSelected: sortKey == key,
            identifier: "\(accessibilityIdentifier)-\(id)"
        ) { sortKey = key }
            .disabled(unavailableKeys.contains(key))
    }

    private func orderRow(_ title: String, _ order: SortMenuOrder, _ id: String) -> some View {
        MenuSelectionRow(
            title,
            isSelected: sortOrder == order,
            identifier: "\(accessibilityIdentifier)-\(id)"
        ) { sortOrder = order }
    }

    public var body: some View {
        CircleIconMenu(
            systemName: "arrow.up.arrow.down",
            accessibilityLabel: String(localized: "Sort"),
            accessibilityIdentifier: accessibilityIdentifier,
            iconColor: iconColor
        ) {
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
                let rows: [(SortMenuKey, String, String)] = [
                    (.name, "name", "Name"),
                    (.modifiedDate, "modifiedDate", "Date Modified"),
                    (.size, "size", "Size")
                ]
                request.handle(
                    host: .files,
                    family: .sortKey,
                    items: rows
                        .filter { unavailableKeys.contains($0.0) == false }
                        .map { key, id, title in
                            DebugMenuSelectionItem(
                                id: id,
                                title: title,
                                isSelected: sortKey == key,
                                select: { sortKey = key }
                            )
                        }
                )
            case .sortOrder:
                request.handle(
                    host: .files,
                    family: .sortOrder,
                    items: [
                        DebugMenuSelectionItem(
                            id: "ascending",
                            title: String(localized: "Ascending"),
                            isSelected: sortOrder == .ascending,
                            select: { sortOrder = .ascending }
                        ),
                        DebugMenuSelectionItem(
                            id: "descending",
                            title: String(localized: "Descending"),
                            isSelected: sortOrder == .descending,
                            select: { sortOrder = .descending }
                        )
                    ]
                )
            default:
                return
            }
        }
#endif
    }

    public init(
        sortKey: Binding<SortMenuKey>,
        sortOrder: Binding<SortMenuOrder>,
        unavailableKeys: Set<SortMenuKey> = [],
        accessibilityIdentifier: String = "DesignSystem-menu-sort"
    ) {
        self._sortKey = sortKey
        self._sortOrder = sortOrder
        self.unavailableKeys = unavailableKeys
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}
