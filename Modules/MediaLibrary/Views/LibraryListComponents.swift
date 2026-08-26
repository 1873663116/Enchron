import DesignSystem
import MediaLibrary
import SwiftUI

public struct FileListGroup: View {
    public enum Kind {
        case video
        case folder

        public var icon: String {
            switch self {
            case .video: "film"
            case .folder: "folder"
            }
        }
    }

    public struct Item: Identifiable {
        public struct ContextAction: Identifiable {
            public let title: String
            public let systemName: String
            public var role: ButtonRole? = nil
            public let action: () -> Void
            public var id: String { "\(title)-\(systemName)" }

            public init(
                title: String,
                systemName: String,
                role: ButtonRole? = nil,
                action: @escaping () -> Void
            ) {
                self.title = title
                self.systemName = systemName
                self.role = role
                self.action = action
            }
        }

        public let id: String
        public let kind: Kind
        public let title: String
        /// Trailing metadata revealed on gaze.
        public let metadata: String?
        public var action: () -> Void = {}
        public var contextActions: [ContextAction] = []
        public var selectionEnabled = false
        public var isSelected = false

        /// Video file variant — gaze reveals `badges · size · duration`.
        public static func video(
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
        public static func folder(
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

    public var accessibilityIdentifier: String = "DesignPreview-FileListGroup"
    public let items: [Item]

    public init(
        accessibilityIdentifier: String = "DesignPreview-FileListGroup",
        items: [Item]
    ) {
        self.items = items
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var cornerRadius: CGFloat { DesignTokens.Radius.element }
    private var groupShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @Namespace private var hoverNamespace

    public var body: some View {
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

public struct FileListGroupRow: View {
    let item: FileListGroup.Item
    let cornerRadius: CGFloat
    let index: Int
    let count: Int
    var hoverNamespace: Namespace.ID?

    public var body: some View {
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

// MARK: - Small elements
