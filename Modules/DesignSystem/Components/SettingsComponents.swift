import SwiftUI

public struct GlassCapsuleIconLabelButton: View {
    let title: String
    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void
    var accessibilityIdentifier: String?

    public init(
        title: String,
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) {
        self.title = title
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        Button(action: action) {
            ButtonIconLabel(title: title, systemName: systemName)
                .foregroundStyle(.white)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(
                    minWidth: DesignTokens.Interactive.regular * 2,
                    minHeight: DesignTokens.Interactive.regular
                )
                .clipShape(Capsule())
                .enchronButtonSurface(in: Capsule())
                .enchronHoverContentShape(Capsule())
                .enchronHoverEffect(.automatic)
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.control))
        .padding(
            .vertical,
            (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2
        )
        .contentShape(Capsule())
        .enchronHoverContentShape(
            Capsule(),
            insets: EdgeInsets(
                top: (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2,
                leading: 0,
                bottom: (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2,
                trailing: 0
            )
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignSystem-button-\(title)")
    }
}

public struct CircleIconLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var visualSize: CGFloat = DesignTokens.Interactive.regular
    var iconTier: ButtonIconTier = .standard
    var accessibilityIdentifier: String?
    var symbolContentTransition: ContentTransition = .identity

    public init(
        systemName: String,
        accessibilityLabel: String,
        iconColor: Color = .white,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        iconTier: ButtonIconTier = .standard,
        accessibilityIdentifier: String? = nil,
        symbolContentTransition: ContentTransition = .identity
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.iconColor = iconColor
        self.visualSize = visualSize
        self.iconTier = iconTier
        self.accessibilityIdentifier = accessibilityIdentifier
        self.symbolContentTransition = symbolContentTransition
    }

    public var body: some View {
        ButtonSymbol(systemName: systemName, tier: iconTier)
            .contentTransition(symbolContentTransition)
            .foregroundStyle(iconColor)
            .frame(width: visualSize, height: visualSize)
            .clipShape(Circle())
            .enchronButtonSurface(in: Circle())
            .enchronHoverContentShape(Circle())
            .enchronHoverEffect(.automatic)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier ?? "DesignSystem-label-\(systemName)")
            .opacity(isEnabled ? 1 : 0.32)
    }
}

public struct CircleIconButton: View {
    private enum SymbolState {
        case expandCollapse(isExpanded: Bool)

        var systemName: String {
            switch self {
            case .expandCollapse(let isExpanded):
                return isExpanded
                    ? "arrow.down.forward.and.arrow.up.backward"
                    : "arrow.up.left.and.arrow.down.right"
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .expandCollapse:
                return "DesignSystem-button-expand-collapse"
            }
        }
    }

    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void = {}
    var accessibilityIdentifier: String?
    var visualSize: CGFloat = DesignTokens.Interactive.regular
    var targetSize: CGFloat = DesignTokens.Interactive.large
    var iconTier: ButtonIconTier = .standard
    private let symbolState: SymbolState?
    private let iconExpansion: Bool?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityPrefersCrossFadeTransitions) private var accessibilityPrefersCrossFadeTransitions

    public init(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        targetSize: CGFloat = DesignTokens.Interactive.large,
        iconTier: ButtonIconTier = .standard
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.visualSize = visualSize
        self.targetSize = targetSize
        self.iconTier = iconTier
        self.symbolState = nil
        self.iconExpansion = nil
    }

    private init(
        symbolState: SymbolState,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        accessibilityIdentifier: String?,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        targetSize: CGFloat = DesignTokens.Interactive.large,
        iconTier: ButtonIconTier = .standard
    ) {
        self.systemName = symbolState.systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.visualSize = visualSize
        self.targetSize = targetSize
        self.iconTier = iconTier
        self.symbolState = symbolState
        self.iconExpansion = nil
    }

    private init(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        accessibilityIdentifier: String?,
        visualSize: CGFloat,
        targetSize: CGFloat,
        iconTier: ButtonIconTier,
        iconExpansion: Bool
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.visualSize = visualSize
        self.targetSize = targetSize
        self.iconTier = iconTier
        self.symbolState = nil
        self.iconExpansion = iconExpansion
    }

    private var renderedSystemName: String {
        symbolState?.systemName ?? systemName
    }

    private var resolvedAccessibilityIdentifier: String {
        accessibilityIdentifier
            ?? symbolState?.accessibilityIdentifier
            ?? "DesignSystem-button-\(systemName)"
    }

    private var symbolContentTransition: ContentTransition {
        if accessibilityReduceMotion {
            return .identity
        }
        if accessibilityPrefersCrossFadeTransitions {
            return .opacity
        }
        return .symbolEffect(.replace)
    }

    private var symbolAnimation: Animation? {
        if accessibilityReduceMotion {
            return nil
        }
        if accessibilityPrefersCrossFadeTransitions {
            return .easeInOut(duration: 0.12)
        }
        return .easeInOut(duration: 0.2)
    }

    private var gearRotationDegrees: Double {
        (iconExpansion == true) ? 360 : 0
    }

    public var body: some View {
        Button(action: action) {
            CircleIconLabel(
                systemName: renderedSystemName,
                accessibilityLabel: accessibilityLabel,
                visualSize: visualSize,
                iconTier: iconTier,
                symbolContentTransition: symbolContentTransition
            )
            .rotationEffect(.degrees(gearRotationDegrees))
            .animation(
                iconExpansion == nil || accessibilityReduceMotion
                    ? nil
                    : DesignTokens.AnimationToken.symbolRotateSpin,
                value: iconExpansion
            )
            .animation(symbolAnimation, value: renderedSystemName)
            .accessibilityHidden(true)
            .frame(width: targetSize, height: targetSize)
            .contentShape(Circle())
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .contentShape(Circle())
        .enchronHoverContentShape(
            Circle(),
            insets: EdgeInsets(
                top: (targetSize - visualSize) / 2,
                leading: (targetSize - visualSize) / 2,
                bottom: (targetSize - visualSize) / 2,
                trailing: (targetSize - visualSize) / 2
            )
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(resolvedAccessibilityIdentifier)
    }

    public static func back(
        accessibilityLabel: String = "Back",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "chevron.left",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func expand(
        accessibilityLabel: String = "Expand",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "arrow.up.left.and.arrow.down.right",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func collapse(
        accessibilityLabel: String = "Collapse",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "arrow.down.forward.and.arrow.up.backward",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func expandCollapse(
        isExpanded: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            symbolState: .expandCollapse(isExpanded: isExpanded),
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func environment(
        accessibilityLabel: String = "Environment",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "mountain.2.fill",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier,
            iconTier: .compact
        )
    }

    public static func settings(
        isExpanded: Bool = false,
        accessibilityLabel: String = "Settings",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "gear",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier,
            visualSize: DesignTokens.Interactive.regular,
            targetSize: DesignTokens.Interactive.large,
            iconTier: .standard,
            iconExpansion: isExpanded
        )
    }

    public static func expandVertically(
        accessibilityLabel: String = "Expand Vertically",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "rectangle.arrowtriangle.2.outward",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func collapseVertically(
        accessibilityLabel: String = "Collapse Vertically",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "rectangle.arrowtriangle.2.inward",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func more(
        accessibilityLabel: String = "More",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "ellipsis",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    public static func close(
        accessibilityLabel: String = "Close",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> CircleIconButton {
        CircleIconButton(
            systemName: "xmark",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

public struct CircleIconMenu<Content: View>: View {
    let systemName: String
    let accessibilityLabel: String
    var accessibilityIdentifier: String?
    var visualSize: CGFloat = DesignTokens.Interactive.regular
    var targetSize: CGFloat = DesignTokens.Interactive.large
    var iconTier: ButtonIconTier = .standard
    var iconColor: Color = .white
    @ViewBuilder var content: () -> Content

    public init(
        systemName: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String? = nil,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        targetSize: CGFloat = DesignTokens.Interactive.large,
        iconTier: ButtonIconTier = .standard,
        iconColor: Color = .white,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.visualSize = visualSize
        self.targetSize = targetSize
        self.iconTier = iconTier
        self.iconColor = iconColor
        self.content = content
    }

    public var body: some View {
        Menu {
            content()
        } label: {
            CircleIconLabel(
                systemName: systemName,
                accessibilityLabel: accessibilityLabel,
                iconColor: iconColor,
                visualSize: visualSize,
                iconTier: iconTier,
                accessibilityIdentifier: accessibilityIdentifier
            )
            .accessibilityHidden(true)
            .frame(width: targetSize, height: targetSize)
            .contentShape(Circle())
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle.menuIcon())
        .contentShape(Circle())
        .enchronHoverContentShape(
            Circle(),
            insets: EdgeInsets(
                top: (targetSize - visualSize) / 2,
                leading: (targetSize - visualSize) / 2,
                bottom: (targetSize - visualSize) / 2,
                trailing: (targetSize - visualSize) / 2
            )
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(
            accessibilityIdentifier ?? "DesignSystem-menu-\(systemName)"
        )
    }
}

public extension View {
    func enchronDestructiveConfirmation(
        _ title: String,
        message: String,
        confirmTitle: String,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            Button(confirmTitle, role: .destructive, action: onConfirm)
                .accessibilityIdentifier("DesignSystem-destructiveConfirmation-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("DesignSystem-destructiveConfirmation-cancel")
        } message: {
            Text(message)
        }
    }

    func enchronErrorDialog(
        _ title: String,
        message: String,
        primaryTitle: String,
        secondaryTitle: String,
        isPresented: Binding<Bool>,
        identifierPrefix: String = "DesignSystem-errorDialog",
        onPrimary: @escaping () -> Void = {},
        onSecondary: @escaping () -> Void = {}
    ) -> some View {
        alert(title, isPresented: isPresented) {
            Button(primaryTitle, action: onPrimary)
                .accessibilityIdentifier("\(identifierPrefix)-primary")
            Button(secondaryTitle, role: .cancel, action: onSecondary)
                .accessibilityIdentifier("\(identifierPrefix)-secondary")
        } message: {
            Text(message)
        }
    }
}

public extension View {
    func enchronListGroupSurface<S: InsettableShape>(
        in shape: S,
        material: Material = .regular
    ) -> some View {
        self
            .background(material, in: shape)
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    DesignTokens.Surface.chromeBorder,
                    lineWidth: DesignTokens.Stroke.subtle
                )
            }
    }

    func enchronListGroupSurface(
        cornerRadius: CGFloat = DesignTokens.Radius.element,
        material: Material = .regular
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return enchronListGroupSurface(in: shape, material: material)
    }
}

public struct SettingListGroup: View {
    public enum ExpansionOrigin {
        case top
        case bottom
        case center

        var anchor: UnitPoint {
            switch self {
            case .top: .top
            case .bottom: .bottom
            case .center: .center
            }
        }
    }

    public enum ActionRole {
        case normal
        case destructive
    }

    public struct MenuOption: Identifiable {
        public let id: String
        public let title: String
        public var role: ButtonRole?
        public var action: () -> Void

        public init(_ title: String, id: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void = {}) {
            self.id = id ?? title
            self.title = title
            self.role = role
            self.action = action
        }
    }

    public enum Accessory {
        case none
        case automatic
        case menu(title: String, options: [MenuOption], role: ActionRole = .normal)
        case action(
            title: String,
            feedback: String?,
            systemName: String?,
            role: ActionRole,
            action: () -> Void
        )
        case toggle(isOn: Bool)
        case boundToggle(isOn: Binding<Bool>, isEnabled: Bool, marker: String?)
        case value(String)
        case valueAction(
            value: String,
            actionTitle: String,
            feedback: String?,
            action: () -> Void
        )
    }

    public struct CardOption: Identifiable {
        public let id: String
        public let title: String
        public let systemName: String

        public init(id: String? = nil, title: String, systemName: String) {
            self.id = id ?? title
            self.title = title
            self.systemName = systemName
        }
    }

    public enum EmbeddedControl {
        case cardSelection(options: [CardOption], selectedID: Binding<String>)
        case centerSlider(
            value: Binding<Int>,
            leadingSystemImage: String,
            trailingSystemImage: String,
            accessibilityLabel: String
        )
        case rangeSlider(
            value: Binding<Double>,
            range: ClosedRange<Double>,
            decimals: Int = 0,
            unit: String? = nil,
            accessibilityLabel: String
        )
    }

    public struct KeyValue: Identifiable {
        public let key: String
        public let value: String
        public var id: String { "\(key)-\(value)" }

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public struct Item: Identifiable {
        public let id: String
        public let title: String
        public let systemName: String?
        public var supportingText: String?
        public var detail: String?
        public var keyValueDetail: [KeyValue]?
        public var expansion: ExpansionOrigin = .top
        public var accessory: Accessory = .automatic
        public var embeddedControl: EmbeddedControl?
        public var action: () -> Void = {}

        public init(
            id: String? = nil,
            title: String,
            systemName: String? = nil,
            supportingText: String? = nil,
            detail: String? = nil,
            keyValueDetail: [KeyValue]? = nil,
            expansion: ExpansionOrigin = .top,
            accessory: Accessory = .automatic,
            embeddedControl: EmbeddedControl? = nil,
            action: @escaping () -> Void = {}
        ) {
            self.id = id ?? "\(systemName ?? "plain")-\(title)"
            self.title = title
            self.systemName = systemName
            self.supportingText = supportingText
            self.detail = detail
            self.keyValueDetail = keyValueDetail
            self.expansion = expansion
            self.accessory = accessory
            self.embeddedControl = embeddedControl
            self.action = action
        }
    }

    public var accessibilityIdentifier: String = "DesignSystem-SettingListGroup"
    let items: [Item]

    private var cornerRadius: CGFloat {
        DesignTokens.Radius.element
    }

    private var groupShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @Namespace private var hoverNamespace

    public init(
        accessibilityIdentifier: String = "DesignSystem-SettingListGroup",
        items: [Item]
    ) {
        self.accessibilityIdentifier = accessibilityIdentifier
        self.items = items
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                SettingListGroupRow(
                    id: item.id,
                    title: item.title,
                    systemName: item.systemName,
                    supportingText: item.supportingText,
                    detail: item.detail,
                    keyValueDetail: item.keyValueDetail,
                    expansion: item.expansion,
                    accessory: item.accessory,
                    embeddedControl: item.embeddedControl,
                    cornerRadius: cornerRadius,
                    index: index,
                    count: items.count,
                    hoverNamespace: hoverNamespace,
                    action: item.action
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

public struct ListGroupRowShell<Content: View>: View {
    let index: Int
    let count: Int
    let cornerRadius: CGFloat
    var hoverNamespace: Namespace.ID?
    var showsHighlight: Bool = true
    var isInteractive: Bool = true
    var accessibilityLabel: String = ""
    var accessibilityValue: String = ""
    var action: () -> Void = {}
    @ViewBuilder var content: (_ rowHoverGroup: EnchronHoverGroup?) -> Content

    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == count - 1 }
    private var showsDivider: Bool { !isLast }

    private var highlightShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? cornerRadius : 0,
            bottomLeadingRadius: isLast ? cornerRadius : 0,
            bottomTrailingRadius: isLast ? cornerRadius : 0,
            topTrailingRadius: isFirst ? cornerRadius : 0,
            style: .continuous
        )
    }

    private func rowGroup(_ rowIndex: Int, _ behavior: EnchronHoverGroup.Behavior) -> EnchronHoverGroup? {
        guard let hoverNamespace else { return nil }
        return EnchronHoverGroup(id: "listGroupRow\(rowIndex)", in: hoverNamespace, behavior: behavior)
    }

    public init(
        index: Int,
        count: Int,
        cornerRadius: CGFloat,
        hoverNamespace: Namespace.ID? = nil,
        showsHighlight: Bool = true,
        isInteractive: Bool = true,
        accessibilityLabel: String = "",
        accessibilityValue: String = "",
        action: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (_ rowHoverGroup: EnchronHoverGroup?) -> Content
    ) {
        self.index = index
        self.count = count
        self.cornerRadius = cornerRadius
        self.hoverNamespace = hoverNamespace
        self.showsHighlight = showsHighlight
        self.isInteractive = isInteractive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.action = action
        self.content = content
    }

    @ViewBuilder
    public var body: some View {
        if isInteractive {
            Button(action: action) { surface }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
        } else {
            surface
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var surface: some View {
        let followGroup = rowGroup(index, .followsGroup)
        if showsHighlight {
            content(followGroup)
                .enchronHoverContentShape(highlightShape)
                .contentShape(.interaction, highlightShape)
                .enchronHoverEffect(.highlight)
                .enchronHoverScale(active: 1.006)
                .enchronHoverActivation(in: rowGroup(index, .activatesGroup))
                .background(alignment: .bottom) { divider }
        } else {
            content(followGroup)
                .background(alignment: .bottom) { divider }
        }
    }

    @ViewBuilder
    private var divider: some View {
        if showsDivider {
            SettingListGroupDivider()
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .enchronHoverOpacity(
                    active: 0,
                    inactive: 1,
                    in: rowGroup(index, .followsGroup)
                )
                .enchronHoverOpacity(
                    active: 0,
                    inactive: 1,
                    in: rowGroup(index + 1, .followsGroup)
                )
        }
    }
}

struct SettingListGroupRow: View {
    let id: String
    let title: String
    let systemName: String?
    var supportingText: String?
    var detail: String?
    var keyValueDetail: [SettingListGroup.KeyValue]?
    var expansion: SettingListGroup.ExpansionOrigin = .top
    var accessory: SettingListGroup.Accessory = .automatic
    var embeddedControl: SettingListGroup.EmbeddedControl?
    let cornerRadius: CGFloat
    let index: Int
    let count: Int
    var hoverNamespace: Namespace.ID?
    var action: () -> Void = {}

    @State private var isExpanded = false
    @State private var selectedMenuTitle: String?
    @State private var feedbackTitle: String?
    @State private var feedbackResetID = UUID()

    private var isExpandable: Bool { detail != nil || keyValueDetail != nil }
    private var isEmbeddedOnly: Bool { embeddedControl != nil && isAccessoryEmpty }
    private var isAccessoryEmpty: Bool {
        if case .none = accessory {
            return true
        }
        return false
    }
    private var embeddedVerticalPadding: CGFloat {
        switch embeddedControl {
        case .centerSlider?, .rangeSlider?:
            return DesignTokens.Spacing.sm
        default:
            return DesignTokens.Spacing.lg
        }
    }
    private var usesRowHover: Bool { usesWholeRowButton }
    private var usesWholeRowButton: Bool {
        if case .automatic = accessory {
            return true
        }
        return false
    }

    @ViewBuilder
    var body: some View {
        ListGroupRowShell(
            index: index,
            count: count,
            cornerRadius: cornerRadius,
            hoverNamespace: hoverNamespace,
            showsHighlight: usesRowHover,
            isInteractive: usesWholeRowButton,
            accessibilityLabel: title,
            accessibilityValue: rowAccessibilityValue,
            action: handleTap
        ) { _ in
            rowSurfaceContent
        }
#if DEBUG
        .onReceive(
            NotificationCenter.default.publisher(for: .debugMenuSelection)
        ) { notification in
            guard let request = notification.object as? DebugMenuSelectionRequest,
                  let family = DebugMenuSelectionFamily(rawValue: id),
                  case .menu(let currentTitle, let options, _) = accessory else {
                return
            }
            request.handle(
                host: .settings,
                family: family,
                items: options.map { option in
                    DebugMenuSelectionItem(
                        id: option.id,
                        title: option.title,
                        isSelected: (selectedMenuTitle ?? currentTitle) == option.title,
                        select: {
                            menuSelection(
                                title: currentTitle,
                                options: options
                            ).wrappedValue = option.title
                        }
                    )
                }
            )
        }
#endif
    }

    private var rowAccessibilityValue: String {
        guard isExpandable else { return "" }
        guard isExpanded else { return "Collapsed" }
        if let keyValueDetail {
            let values = keyValueDetail
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            return "Expanded, \(values)"
        }
        if let detail {
            return "Expanded, \(detail)"
        }
        return "Expanded"
    }

    private var rowSurfaceContent: some View {
        VStack(spacing: 0) {
            if isEmbeddedOnly {
                if let embeddedControl {
                    embeddedControlView(embeddedControl)
                        .padding(.vertical, embeddedVerticalPadding)
                }
            } else {
                rowContent

                if isExpanded {
                    if let keyValueDetail {
                        expandedKeyValues(keyValueDetail)
                            .transition(expansionTransition)
                    } else if let detail {
                        expandedDetail(detail)
                            .transition(expansionTransition)
                    }
                }

                if let embeddedControl {
                    embeddedControlView(embeddedControl)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        .padding(.bottom, DesignTokens.Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(DesignTokens.AnimationToken.selection, value: isExpanded)
    }

    private var rowContent: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if let systemName {
                Image(systemName: systemName)
                    .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                    .foregroundStyle(DesignTokens.Surface.accessoryText)
                    .frame(width: DesignTokens.Interactive.compact)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(DesignTokens.Typography.selectionHeader)
                    .foregroundStyle(DesignTokens.Surface.selectionHeaderText)

                if let supportingText {
                    Text(supportingText)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DesignTokens.Spacing.lg)

            trailingAccessory
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: DesignTokens.Interactive.rowHeight)
    }

    private func menuSelection(
        title: String,
        options: [SettingListGroup.MenuOption]
    ) -> Binding<String> {
        Binding(
            get: { selectedMenuTitle ?? title },
            set: { newTitle in
                guard let option = options.first(where: { $0.title == newTitle }) else { return }
                selectedMenuTitle = newTitle
                option.action()
            }
        )
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch accessory {
        case .none:
            EmptyView()

        case .automatic:
            Image(systemName: "chevron.right")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                .rotationEffect(isExpandable && isExpanded ? .degrees(90) : .zero)

        case .menu(let title, let options, let role):
            Menu {
                if options.isEmpty {
                    Text("No Options")
                } else {
                    ForEach(options) { option in
                        MenuSelectionRow(
                            option.title,
                            isSelected: (selectedMenuTitle ?? title) == option.title,
                            identifier: "Settings-menuOption-\(id)-\(option.id)"
                        ) {
                            selectedMenuTitle = option.title
                            option.action()
                        }
                    }
                }
            } label: {
                SettingListActionChip(
                    title: selectedMenuTitle ?? title,
                    systemName: "chevron.up.chevron.down",
                    role: role
                )
            }
            .buttonStyle(.plain)
            .frame(minHeight: DesignTokens.Interactive.large)
            .enchronHoverContentShape(
                Capsule(),
                insets: EdgeInsets(
                    top: (DesignTokens.Interactive.large - DesignTokens.Interactive.compact) / 2,
                    leading: 0,
                    bottom: (DesignTokens.Interactive.large - DesignTokens.Interactive.compact) / 2,
                    trailing: 0
                )
            )
            .contentShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
            .accessibilityIdentifier("Settings-menu-\(id)")

        case .action(let title, let feedback, let systemName, let role, let action):
            SettingListAccessoryButton(accessibilityLabel: title) {
                action()
                showFeedback(feedback)
            } label: {
                SettingListActionChip(
                    title: feedbackTitle ?? title,
                    systemName: feedbackTitle == nil ? systemName : "checkmark",
                    role: role
                )
            }
            .accessibilityIdentifier("Settings-action-\(id)")

        case .toggle(let isOn):
            GlassToggle(isOn: isOn)
                .accessibilityLabel(title)

        case .boundToggle(let isOn, let isEnabled, let marker):
            HStack(spacing: DesignTokens.Spacing.xs) {
                if let marker {
                    Text(marker)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }

                BoundGlassToggle(isOn: isOn, isEnabled: isEnabled)
                    .accessibilityLabel(title)
            }

        case .value(let text):
            Text(text)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .lineLimit(1)

        case .valueAction(let value, let actionTitle, let feedback, let action):
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(value)
                    .font(DesignTokens.Typography.sectionHeader)
                    .foregroundStyle(DesignTokens.Surface.accessoryText)
                    .lineLimit(1)

                SettingListAccessoryButton(accessibilityLabel: actionTitle) {
                    action()
                    showFeedback(feedback)
                } label: {
                    SettingListActionChip(
                        title: feedbackTitle ?? actionTitle,
                        systemName: feedbackTitle == nil ? nil : "checkmark"
                    )
                }
                .accessibilityIdentifier("Settings-action-\(id)")
            }
        }
    }

    @ViewBuilder
    private func embeddedControlView(_ control: SettingListGroup.EmbeddedControl) -> some View {
        switch control {
        case .cardSelection(let options, let selectedID):
            SettingListCardSelectionGrid(options: options, selectedID: selectedID)

        case .centerSlider(let value, let leadingSystemImage, let trailingSystemImage, let accessibilityLabel):
            SettingListCenterSliderRow(
                value: value,
                title: title,
                leadingSystemImage: leadingSystemImage,
                trailingSystemImage: trailingSystemImage,
                accessibilityLabel: accessibilityLabel
            )

        case .rangeSlider(let value, let range, let decimals, let unit, let accessibilityLabel):
            SettingListRangeSliderRow(
                value: value,
                range: range,
                decimals: decimals,
                unit: unit,
                title: title,
                accessibilityLabel: accessibilityLabel
            )
        }
    }

    private func expandedDetail(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.sectionHeader)
            .foregroundStyle(DesignTokens.Surface.supportingText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)
    }

    private func expandedKeyValues(_ rows: [SettingListGroup.KeyValue]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                    Text(row.key)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                        .frame(width: 160, alignment: .leading)

                    Text(row.value)
                        .font(DesignTokens.Typography.sectionHeader)
                        .foregroundStyle(DesignTokens.Surface.accessoryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.bottom, DesignTokens.Spacing.md)
    }

    private var expansionTransition: AnyTransition {
        let scaled = AnyTransition
            .scale(scale: 0.96, anchor: expansion.anchor)
            .combined(with: .opacity)

        switch expansion {
        case .top:
            return .asymmetric(insertion: scaled.combined(with: .move(edge: .top)), removal: .opacity)
        case .bottom:
            return .asymmetric(insertion: scaled.combined(with: .move(edge: .bottom)), removal: .opacity)
        case .center:
            return .asymmetric(insertion: scaled, removal: .opacity)
        }
    }

    private func handleTap() {
        guard isExpandable else {
            action()
            return
        }
        withAnimation(DesignTokens.AnimationToken.selection) {
            isExpanded.toggle()
        }
    }

    private func showFeedback(_ feedback: String?) {
        guard let feedback else { return }

        let resetID = UUID()
        feedbackResetID = resetID
        withAnimation(DesignTokens.AnimationToken.selection) {
            feedbackTitle = feedback
        }

        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            await MainActor.run {
                guard feedbackResetID == resetID else { return }
                withAnimation(DesignTokens.AnimationToken.selection) {
                    feedbackTitle = nil
                }
            }
        }
    }
}

public struct SettingListGroupDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(DesignTokens.Surface.divider)
            .frame(height: DesignTokens.Stroke.regular)
            .accessibilityHidden(true)
    }
}

private struct SettingListCardSelectionGrid: View {
    let options: [SettingListGroup.CardOption]
    @Binding var selectedID: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 0)

            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                if index > 0 {
                    Spacer(minLength: 0)
                }

                VStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        withAnimation(DesignTokens.AnimationToken.selection) {
                            selectedID = option.id
                        }
                    } label: {
                        SettingListCardSelectionCard(
                            option: option,
                            isSelected: selectedID == option.id
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: cardWidth)
                    .accessibilityLabel(option.title)
                    .accessibilityValue(selectedID == option.id ? "Selected" : "Not selected")

                    Text(option.title)
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .allowsHitTesting(false)

                    SettingListSelectionIndicator(isSelected: selectedID == option.id)
                        .allowsHitTesting(false)
                }
                .frame(width: cardWidth)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var cardWidth: CGFloat {
        options.count <= 2 ? 160 : 132
    }
}

private struct SettingListCenterSliderRow: View {
    @Binding var value: Int
    let title: String
    let leadingSystemImage: String
    let trailingSystemImage: String
    let accessibilityLabel: String

    @Namespace private var hoverNamespace
    @State private var rowWidth: CGFloat = 0
    @State private var isDragging = false

    private var resolvedTrackWidth: CGFloat {
        let sidePadding = DesignTokens.Spacing.lg * 2
        let iconColumns = DesignTokens.Interactive.compact * 2
        let spacings = DesignTokens.Spacing.md * 2
        return max(rowWidth - sidePadding - iconColumns - spacings, 200)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.selectionHeader)
                .foregroundStyle(DesignTokens.Surface.selectionHeaderText)
                .lineLimit(1)
                .enchronHoverOpacity(
                    active: 1,
                    inactive: 0,
                    in: hoverGroup(.followsGroup),
                    forcedActive: isDragging
                )

            CenterSlider(
                value: $value,
                leadingSystemImage: leadingSystemImage,
                trailingSystemImage: trailingSystemImage,
                accessibilityLabel: accessibilityLabel,
                trackWidth: resolvedTrackWidth,
                onDraggingChanged: { isDragging = $0 }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in rowWidth = newValue }
            }
        }
        .enchronHoverContentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.element, style: .continuous))
        .enchronHoverActivation(in: hoverGroup(.activatesGroup))
    }

    private func hoverGroup(_ behavior: EnchronHoverGroup.Behavior) -> EnchronHoverGroup? {
        EnchronHoverGroup(id: "settingListCenterSliderLabel", in: hoverNamespace, behavior: behavior)
    }
}

private struct SettingListRangeSliderRow: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let decimals: Int
    let unit: String?
    let title: String
    let accessibilityLabel: String

    @Namespace private var hoverNamespace
    @State private var rowWidth: CGFloat = 0
    @State private var isDragging = false

    private var resolvedTrackWidth: CGFloat {
        let sidePadding = DesignTokens.Spacing.lg * 2
        return max(rowWidth - sidePadding, 200)
    }

    private var readout: String {
        let number = value.formatted(.number.precision(.fractionLength(decimals)))
        if let unit {
            return "\(number) \(unit)"
        }
        return number
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(title)
                    .font(DesignTokens.Typography.selectionHeader)
                    .foregroundStyle(DesignTokens.Surface.selectionHeaderText)
                    .lineLimit(1)
                Spacer(minLength: DesignTokens.Spacing.sm)
                Text(readout)
                    .font(DesignTokens.Typography.selectionHeader)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Surface.selectionHeaderText)
                    .lineLimit(1)
            }
            .enchronHoverOpacity(
                active: 1,
                inactive: 0,
                in: hoverGroup(.followsGroup),
                forcedActive: isDragging
            )

            RangeSlider(
                value: $value,
                range: range,
                accessibilityLabel: accessibilityLabel,
                accessibilityValue: readout,
                trackWidth: resolvedTrackWidth,
                onDraggingChanged: { isDragging = $0 }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in rowWidth = newValue }
            }
        }
        .enchronHoverContentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.element, style: .continuous))
        .enchronHoverActivation(in: hoverGroup(.activatesGroup))
    }

    private func hoverGroup(_ behavior: EnchronHoverGroup.Behavior) -> EnchronHoverGroup? {
        EnchronHoverGroup(id: "settingListRangeSliderLabel", in: hoverNamespace, behavior: behavior)
    }
}

private struct SettingListCardSelectionCard: View {
    let option: SettingListGroup.CardOption
    let isSelected: Bool

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
    }

    var body: some View {
        cardShape
            .fill(DesignTokens.Surface.elevated)
            .frame(height: 86)
            .overlay {
                Image(systemName: option.systemName)
                    .font(DesignTokens.SymbolSize.card)
                    .foregroundStyle(isSelected ? DesignTokens.Theme.accent : .secondary)
            }
            .overlay {
                cardShape.stroke(
                    isSelected ? DesignTokens.Theme.accent : DesignTokens.Surface.divider,
                    lineWidth: isSelected ? DesignTokens.Stroke.bold : DesignTokens.Stroke.subtle
                )
            }
            .enchronHoverContentShape(cardShape)
            .enchronHoverEffect(.highlight)
            .contentShape(.interaction, cardShape)
    }
}

private struct SettingListSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        selectionIndicator
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Circle()
                .fill(DesignTokens.Theme.accent)
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
        } else {
            Circle()
                .stroke(DesignTokens.SourceSidebar.selectionIndicator, lineWidth: DesignTokens.Stroke.regular)
                .frame(width: 22, height: 22)
        }
    }
}

private struct SettingListActionChip: View {
    let title: String
    var systemName: String?
    var role: SettingListGroup.ActionRole = .normal

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if let systemName {
                ButtonSymbol(systemName: systemName, tier: .label)
            }

            Text(title)
                .id(title)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .font(DesignTokens.Typography.sectionHeader)
        .foregroundStyle(role == .destructive ? .red : DesignTokens.Surface.accessoryText)
        .lineLimit(1)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.Interactive.compact)
        .enchronButtonSurface(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .contentShape(.interaction, Capsule())
        .animation(DesignTokens.AnimationToken.selection, value: title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

private struct SettingListAccessoryButton<Label: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .frame(minHeight: DesignTokens.Interactive.large)
        .enchronHoverContentShape(
            Capsule(),
            insets: EdgeInsets(
                top: (DesignTokens.Interactive.large - DesignTokens.Interactive.compact) / 2,
                leading: 0,
                bottom: (DesignTokens.Interactive.large - DesignTokens.Interactive.compact) / 2,
                trailing: 0
            )
        )
        .accessibilityLabel(accessibilityLabel)
    }
}
