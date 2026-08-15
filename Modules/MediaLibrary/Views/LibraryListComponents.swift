import DesignSystem
import MediaLibrary
import SwiftUI

struct FileListGroup: View {
    enum Kind {
        case video
        case folder

        var icon: String {
            switch self {
            case .video: "film"
            case .folder: "folder"
            }
        }
    }

    struct Item: Identifiable {
        struct ContextAction: Identifiable {
            let title: String
            let systemName: String
            var role: ButtonRole? = nil
            let action: () -> Void
            var id: String { "\(title)-\(systemName)" }
        }

        let id: String
        let kind: Kind
        let title: String
        /// Trailing metadata revealed on gaze.
        let metadata: String?
        var action: () -> Void = {}
        var contextActions: [ContextAction] = []
        var selectionEnabled = false
        var isSelected = false

        /// Video file variant — gaze reveals `badges · size · duration`.
        static func video(
            id: String? = nil,
            title: String,
            fileSize: String,
            duration: String,
            badges: [String] = [],
            contextActions: [ContextAction] = [],
            selectionEnabled: Bool = false,
            isSelected: Bool = false,
            action: @escaping () -> Void = {}
        ) -> Item {
            Item(
                id: id ?? "video-\(title)",
                kind: .video,
                title: title,
                metadata: (badges + [fileSize, duration]).joined(separator: " · "),
                action: action,
                contextActions: contextActions,
                selectionEnabled: selectionEnabled,
                isSelected: isSelected
            )
        }

        /// Folder variant — gaze reveals the item count.
        static func folder(
            id: String? = nil,
            title: String,
            itemCount: Int?,
            contextActions: [ContextAction] = [],
            action: @escaping () -> Void = {}
        ) -> Item {
            Item(
                id: id ?? "folder-\(title)",
                kind: .folder,
                title: title,
                metadata: itemCount.map { "\($0) items" },
                action: action,
                contextActions: contextActions
            )
        }
    }

    var accessibilityIdentifier: String = "DesignPreview-FileListGroup"
    let items: [Item]

    private var cornerRadius: CGFloat { DesignTokens.Radius.element }
    private var groupShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @Namespace private var hoverNamespace

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                FileListGroupRow(
                    item: item,
                    cornerRadius: cornerRadius,
                    index: index,
                    count: items.count,
                    hoverNamespace: hoverNamespace
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .enchronListGroupSurface(cornerRadius: cornerRadius)
        .contentShape(groupShape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct FileListGroupRow: View {
    let item: FileListGroup.Item
    let cornerRadius: CGFloat
    let index: Int
    let count: Int
    var hoverNamespace: Namespace.ID?

    var body: some View {
        ListGroupRowShell(
            index: index,
            count: count,
            cornerRadius: cornerRadius,
            hoverNamespace: hoverNamespace,
            showsHighlight: true,
            isInteractive: true,
            accessibilityLabel: item.title,
            action: item.action
        ) { rowHoverGroup in
            rowContent(reveal: rowHoverGroup)
        }
        .contextMenu {
            ForEach(item.contextActions) { contextAction in
                Button(
                    contextAction.title,
                    systemImage: contextAction.systemName,
                    role: contextAction.role,
                    action: contextAction.action
                )
            }
        }
        .accessibilityIdentifier(item.id)
        .accessibilityAddTraits(item.isSelected ? .isSelected : [])
        .accessibilityValue(
            item.isSelected ? "Selected" : "Not selected",
            isEnabled: item.selectionEnabled
        )
    }

    private func rowContent(reveal rowHoverGroup: EnchronHoverGroup?) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: item.kind.icon)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .frame(width: DesignTokens.Interactive.compact)

            if item.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Theme.accent)
                    .accessibilityHidden(true)
            }

            Text(item.title)
                .font(DesignTokens.Typography.selectionHeader)
                .foregroundStyle(DesignTokens.Surface.selectionHeaderText)

            Spacer(minLength: DesignTokens.Spacing.lg)

            metadataView(reveal: rowHoverGroup)
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: DesignTokens.Interactive.rowHeight)
    }

    @ViewBuilder
    private func metadataView(reveal rowHoverGroup: EnchronHoverGroup?) -> some View {
        if let metadata = item.metadata {
            let label = Text(metadata)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .lineLimit(1)

            if let rowHoverGroup {
                label
                    .enchronHoverOpacity(
                        active: 1,
                        inactive: 0,
                        in: rowHoverGroup,
                        animation: DesignTokens.AnimationToken.controlsTransition
                    )
                    .allowsHitTesting(false)
            } else {
                label.allowsHitTesting(false)
            }
        }
    }
}

struct UncountedFolderGridCard: View {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    @Namespace private var hoverNamespace

    private var shape: RoundedRectangle {
        DesignTokens.ShapeToken.card
    }

    private var hoverGroup: EnchronHoverGroup {
        EnchronHoverGroup(
            id: "uncounted-folder-grid-card",
            in: hoverNamespace,
            behavior: .activatesGroup
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            shape
                .fill(DesignTokens.Surface.elevated)
                .overlay {
                    Image(systemName: "folder.fill")
                        .font(.system(size: DesignTokens.Card.placeholderIconSize))
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
                .frame(
                    width: DesignTokens.Card.gridMin,
                    height: DesignTokens.Card.thumbnailHeight
                )
                .clipShape(shape)
                .enchronHoverContentShape(shape)
                .enchronHoverEffect(.highlight, in: hoverGroup)

            Text(title)
                .font(DesignTokens.Typography.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                .padding(.horizontal, DesignTokens.Card.paddingH)
                .padding(.vertical, DesignTokens.Card.paddingV)
        }
        .frame(width: DesignTokens.Card.gridMin)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel("\(title), folder")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

// MARK: - Small elements
