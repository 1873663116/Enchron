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
        let metadata: String
        var action: () -> Void = {}
        var contextActions: [ContextAction] = []

        /// Video file variant — gaze reveals `badges · size · duration`.
        static func video(
            id: String? = nil,
            title: String,
            fileSize: String,
            duration: String,
            badges: [String] = [],
            contextActions: [ContextAction] = [],
            action: @escaping () -> Void = {}
        ) -> Item {
            Item(
                id: id ?? "video-\(title)",
                kind: .video,
                title: title,
                metadata: (badges + [fileSize, duration]).joined(separator: " · "),
                action: action,
                contextActions: contextActions
            )
        }

        /// Folder variant — gaze reveals the item count.
        static func folder(
            id: String? = nil,
            title: String,
            itemCount: Int,
            contextActions: [ContextAction] = [],
            action: @escaping () -> Void = {}
        ) -> Item {
            Item(
                id: id ?? "folder-\(title)",
                kind: .folder,
                title: title,
                metadata: "\(itemCount) items",
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
    }

    private func rowContent(reveal rowHoverGroup: EnchronHoverGroup?) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: item.kind.icon)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .frame(width: DesignTokens.Interactive.compact)

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
        let label = Text(item.metadata)
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

// MARK: - Small elements

