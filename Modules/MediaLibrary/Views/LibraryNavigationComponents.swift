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

public struct CategorySidebarItem: Identifiable, Equatable {
    public enum StatusLight: Equatable {
        case green
        case yellow
        case red
    }

    public let id: String
    public let icon: String
    public let title: String
    public var statusLight: StatusLight?
    public var accessibilityIdentifier: String?
    public var accessibilityValue: String?

    public init(
        id: String,
        icon: String,
        title: String,
        statusLight: StatusLight? = nil,
        accessibilityIdentifier: String? = nil,
        accessibilityValue: String? = nil
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.statusLight = statusLight
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityValue = accessibilityValue
    }
}

public struct CategorySidebar: View {
    let items: [CategorySidebarItem]
    @Binding var selection: String
    var title: String = "Categories"
    var width: CGFloat = DesignTokens.SourceSidebar.width
    var height: CGFloat?
    var containerIdentifier: String = "CategorySidebar"
    var identifierPrefix: String = "CategorySidebar"
    var onAdd: (() -> Void)?
    var addButtonIdentifier: String?

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.SourceSidebar.headerContentGap) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(title)
                        .font(DesignTokens.SourceSidebar.sectionTitleFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    if let onAdd {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .frame(
                                    width: DesignTokens.Interactive.large,
                                    height: DesignTokens.Interactive.large
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(addButtonIdentifier ?? "\(identifierPrefix)-add")
                    } else {
                        Color.clear
                            .frame(width: DesignTokens.Interactive.large,
                                   height: DesignTokens.Interactive.large)
                            .accessibilityHidden(true)
                    }
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
                        .overlay(alignment: .trailing) {
                            if let statusLight = item.statusLight {
                                StatusLightDot(light: statusLight)
                                    .padding(.trailing, DesignTokens.SourceSidebar.listPaddingH)
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.accessibilityValue ?? "")
                        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                        .accessibilityIdentifier(item.accessibilityIdentifier ?? "\(identifierPrefix)-category-\(item.id)")
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
        identifierPrefix: String = "CategorySidebar",
        onAdd: (() -> Void)? = nil,
        addButtonIdentifier: String? = nil
    ) {
        self.items = items
        self._selection = selection
        self.title = title
        self.width = width
        self.height = height
        self.containerIdentifier = containerIdentifier
        self.identifierPrefix = identifierPrefix
        self.onAdd = onAdd
        self.addButtonIdentifier = addButtonIdentifier
    }
}

private struct StatusLightDot: View {
    let light: CategorySidebarItem.StatusLight

    var body: some View {
        Circle()
            .fill(color)
            .frame(
                width: DesignTokens.Interactive.statusDotSize,
                height: DesignTokens.Interactive.statusDotSize
            )
    }

    private var color: Color {
        switch light {
        case .green: .green
        case .yellow: .yellow
        case .red: .red
        }
    }
}
