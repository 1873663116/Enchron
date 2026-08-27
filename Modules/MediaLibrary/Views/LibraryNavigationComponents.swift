import DesignSystem
import Foundation
import MediaLibrary
import SwiftUI

public struct PathBreadcrumbMenu: View {
    let path: [String]
    var onSelectLevel: (Int) -> Void = { _ in }
    var accessibilityIdentifier = "DesignSystem-breadcrumb-current"

    private var currentFolder: String {
        path.last ?? ""
    }

    public var body: some View {
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

    public init(
        path: [String],
        onSelectLevel: @escaping (Int) -> Void = { _ in },
        accessibilityIdentifier: String = "DesignSystem-breadcrumb-current"
    ) {
        self.path = path
        self.onSelectLevel = onSelectLevel
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public struct SearchInputCapsule: View {
    @Binding var text: String
    var placeholder = "Search"
    var accessibilityIdentifier = "DesignSystem-input-search"

    public var body: some View {
        GlassSearchField(
            text: $text,
            placeholder: placeholder,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public init(
        text: Binding<String>,
        placeholder: String = "Search",
        accessibilityIdentifier: String = "DesignSystem-input-search"
    ) {
        self._text = text
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public struct CategorySidebarItem: Identifiable, Equatable {
    public let id: String
    public let icon: String
    public let title: String

    public init(
        id: String,
        icon: String,
        title: String
    ) {
        self.id = id
        self.icon = icon
        self.title = title
    }
}

public struct CategorySidebar: View {
    let items: [CategorySidebarItem]
    @Binding var selection: String
    var title: String = "Categories"
    var width: CGFloat = DesignTokens.SourceSidebar.width
    var height: CGFloat? = nil
    var containerIdentifier: String = "CategorySidebar"
    var identifierPrefix: String = "CategorySidebar"

    public var body: some View {
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

    public init(
        items: [CategorySidebarItem],
        selection: Binding<String>,
        title: String = "Categories",
        width: CGFloat = DesignTokens.SourceSidebar.width,
        height: CGFloat? = nil,
        containerIdentifier: String = "CategorySidebar",
        identifierPrefix: String = "CategorySidebar"
    ) {
        self.items = items
        self._selection = selection
        self.title = title
        self.width = width
        self.height = height
        self.containerIdentifier = containerIdentifier
        self.identifierPrefix = identifierPrefix
    }
}
