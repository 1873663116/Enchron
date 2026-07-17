import SwiftUI

// swiftlint:disable file_length
// Consolidated shared component library (used by both the app screens and the
// DesignPreview Canvas). Splitting into per-component-family files is tracked
// as separate hygiene; the file_length rule is waived here, not globally.

// MARK: - Shared components used by the Design System review pages

// MARK: - Reusable controls

struct GlassCircleIconLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var visualSize: CGFloat = DesignTokens.Interactive.regular
    var font: Font = DesignTokens.SymbolSize.control
    var accessibilityIdentifier: String?

    // 纯视觉:玻璃圆 + 注视高亮 + press,命中区恒等于视觉圆。命中区的静默扩展由
    // 手势包装层(GlassCircleIconButton)负责——不在 label 内撑大 interaction 区,
    // 否则外层 Button/Menu 会把 hover 套到扩展区,产生一圈多余的注视高亮。
    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundStyle(iconColor)
            .frame(width: visualSize, height: visualSize)
            .clipShape(Circle())
            .glassBackgroundEffect(in: Circle())
            .enchronHoverContentShape(Circle())
            .enchronHoverEffect(.automatic)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-label-\(systemName)")
            .opacity(isEnabled ? 1 : 0.32)
    }
}

struct GlassCircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var action: () -> Void = {}
    var accessibilityIdentifier: String?
    var visualSize: CGFloat = DesignTokens.Interactive.regular
    var targetSize: CGFloat = DesignTokens.Interactive.large
    var font: Font = DesignTokens.SymbolSize.control

    // iconColor 锁死:按钮永远白色图标,不暴露给调用点(Label 默认即 .white)。
    // 原生 Button 负责唯一的激活与辅助功能语义;视觉 label 自己限定 hover 圆,
    // 外层 frame 只扩大静默命中区。

    var body: some View {
        Button(action: action) {
            GlassCircleIconLabel(
                systemName: systemName,
                accessibilityLabel: accessibilityLabel,
                visualSize: visualSize,
                font: font
            )
            .accessibilityHidden(true)
            .frame(width: targetSize, height: targetSize)
            .contentShape(Circle())
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-button-\(systemName)")
    }

    // MARK: 具名图标预设(组装约定:优先调预设;没有预设才传裸 systemName,且顺手补一个预设)

    static func back(
        accessibilityLabel: String = "Back",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> GlassCircleIconButton {
        GlassCircleIconButton(
            systemName: "chevron.left",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    static func expand(
        accessibilityLabel: String = "Expand",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> GlassCircleIconButton {
        GlassCircleIconButton(
            systemName: "arrow.up.left.and.arrow.down.right",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    static func more(
        accessibilityLabel: String = "More",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> GlassCircleIconButton {
        GlassCircleIconButton(
            systemName: "ellipsis",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    static func close(
        accessibilityLabel: String = "Close",
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil
    ) -> GlassCircleIconButton {
        GlassCircleIconButton(
            systemName: "xmark",
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

extension View {
    /// Presents a system confirmation alert for a destructive or sensitive action.
    ///
    /// Built on visionOS's native `.alert`, so the system owns presentation,
    /// centering, glass material, background dimming, and the default focus on
    /// Cancel. The confirm button's red comes from `ButtonRole.destructive`,
    /// resolved at render time by the alert container — no color is authored here,
    /// so no color token is involved. Title and description are shown; the Cancel
    /// button is fixed, only the confirm label is configurable.
    ///
    /// Alert sizing is system-managed; this surface intentionally exposes no size.
    func enchronDestructiveConfirmation(
        _ title: String,
        message: String,
        confirmTitle: String,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            Button(confirmTitle, role: .destructive, action: onConfirm)
                .accessibilityIdentifier("DesignPreview-destructiveConfirmation-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("DesignPreview-destructiveConfirmation-cancel")
        } message: {
            Text(message)
        }
    }

    /// Non-destructive two-action error dialog (e.g. File Browser / playback load
    /// failures): a primary retry action plus a dismiss action, presented from the
    /// same system `.alert` surface as `enchronDestructiveConfirmation`. No colors
    /// are authored here; the system resolves button styling. Sizing is system
    /// managed, so no size is exposed.
    func enchronErrorDialog(
        _ title: String,
        message: String,
        primaryTitle: String,
        secondaryTitle: String,
        isPresented: Binding<Bool>,
        identifierPrefix: String = "DesignPreview-errorDialog",
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

extension View {
    /// The translucent rounded-rect surface shared by `SettingListGroup` and the
    /// expanded precision-timeline card: `.regularMaterial` fill, clipped to a
    /// continuous rounded rectangle, with a 1pt divider stroke. Centralised so
    /// both containers stay identical instead of re-implementing the treatment.
    func enchronListGroupSurface(
        cornerRadius: CGFloat = DesignTokens.Radius.element
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.regularMaterial, in: shape)
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    DesignTokens.Surface.divider,
                    lineWidth: DesignTokens.Stroke.subtle
                )
            }
    }
}

struct SettingListGroup: View {
    /// Where an expanding row's detail panel visually originates. A row near the
    /// top of a container grows *downward* from its top edge; one near the bottom
    /// grows *upward* from its bottom edge; a middle row scales out from its
    /// centre. Only the disclosure motion differs — the panel always lays out
    /// below the row header.
    enum ExpansionOrigin {
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

    enum ActionRole {
        case normal
        case destructive
    }

    struct MenuOption: Identifiable {
        let id: String
        let title: String
        var role: ButtonRole?
        var action: () -> Void

        init(_ title: String, id: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void = {}) {
            self.id = id ?? title
            self.title = title
            self.role = role
            self.action = action
        }
    }

    enum Accessory {
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
        /// Trailing glass toggle. The initial state seeds `GlassToggle`, which owns
        /// the flip interaction.
        case toggle(isOn: Bool)
        case boundToggle(isOn: Binding<Bool>, isEnabled: Bool, marker: String?)
        /// Read-only trailing value (e.g. a cache size or version string).
        case value(String)
        /// Read-only value paired with a trailing action chip (e.g. version + Copy).
        /// On tap the value position briefly shows `feedback`.
        case valueAction(
            value: String,
            actionTitle: String,
            feedback: String?,
            action: () -> Void
        )
    }

    struct CardOption: Identifiable {
        let id: String
        let title: String
        let systemName: String

        init(id: String? = nil, title: String, systemName: String) {
            self.id = id ?? title
            self.title = title
            self.systemName = systemName
        }
    }

    enum EmbeddedControl {
        case cardSelection(options: [CardOption], selectedID: Binding<String>)
        case centerSlider(
            value: Binding<Int>,
            leadingSystemImage: String,
            trailingSystemImage: String,
            accessibilityLabel: String
        )
        /// Leading-origin continuous slider over an arbitrary `range`, paired with
        /// a numeric readout (`decimals` places, optional trailing `unit`). Shares
        /// the `GlassSliderRail` visual with `centerSlider` and the timeline zoom
        /// slider; unlike `centerSlider` it is not detented and carries its own
        /// value domain rather than the fixed -5…5 detents.
        case rangeSlider(
            value: Binding<Double>,
            range: ClosedRange<Double>,
            decimals: Int = 0,
            unit: String? = nil,
            accessibilityLabel: String
        )
    }

    /// One row of an expandable key-value detail panel (diagnostic disclosures).
    struct KeyValue: Identifiable {
        let key: String
        let value: String
        var id: String { "\(key)-\(value)" }
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let systemName: String?
        var supportingText: String? = nil
        /// Descriptive copy revealed when the row expands. `nil` keeps the row a
        /// plain tappable entry that fires `action` instead of disclosing.
        var detail: String? = nil
        /// Key-value rows revealed when the row expands, used for diagnostic
        /// disclosures. Takes precedence over `detail` when both are set.
        var keyValueDetail: [KeyValue]? = nil
        var expansion: ExpansionOrigin = .top
        var accessory: Accessory = .automatic
        var embeddedControl: EmbeddedControl?
        var action: () -> Void = {}

        init(
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

    var accessibilityIdentifier: String = "DesignPreview-SettingListGroup"
    let items: [Item]

    private var cornerRadius: CGFloat {
        DesignTokens.Radius.element
    }

    private var groupShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // Shared across all rows so each separator can follow the gaze hover of
    // *both* of its neighbouring rows (cross-row coordination needs a common
    // namespace; visionOS does not expose gaze hover state to app code).
    @Namespace private var hoverNamespace

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                SettingListGroupRow(
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

/// Shared row chrome for list groups (settings rows & file rows): concentric
/// corner gaze highlight, cross-row separator fade, optional whole-row button.
/// The row content is supplied by the caller; this shell owns only the
/// hover / divider / hit-target chrome so every list group reads identically.
///
/// The content closure receives this row's `followsGroup` handle so a child
/// (e.g. a file row's trailing metadata) can fade in sync with the same gaze
/// the shell highlights on.
struct ListGroupRowShell<Content: View>: View {
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

    // Concentric corner rounding: round only the outer corners (matching the
    // container clip) so the highlight aligns with the group edge and sits
    // square against the separators on its inner edges.
    private var highlightShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? cornerRadius : 0,
            bottomLeadingRadius: isLast ? cornerRadius : 0,
            bottomTrailingRadius: isLast ? cornerRadius : 0,
            topTrailingRadius: isFirst ? cornerRadius : 0,
            style: .continuous
        )
    }

    /// The hover-effect group owned by the row at `rowIndex`. A row *activates*
    /// its own group when gazed; a separator (or trailing metadata) *follows* it.
    private func rowGroup(_ rowIndex: Int, _ behavior: EnchronHoverGroup.Behavior) -> EnchronHoverGroup? {
        guard let hoverNamespace else { return nil }
        return EnchronHoverGroup(id: "listGroupRow\(rowIndex)", in: hoverNamespace, behavior: behavior)
    }

    @ViewBuilder
    var body: some View {
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
                // No-op trigger: gazing this row activates its own group so the
                // separators on both sides (which follow this group) fade in sync
                // with the highlight — same system-composited phase, same timing.
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
                // Follows both bordering rows: row `index` (above) and
                // row `index + 1` (below). Either one's hover fades it.
                .enchronHoverOpacity(
                    active: 0,
                    inactive: 1,
                    in: rowGroup(index, .followsGroup),
                    macShowsActive: false
                )
                .enchronHoverOpacity(
                    active: 0,
                    inactive: 1,
                    in: rowGroup(index + 1, .followsGroup),
                    macShowsActive: false
                )
        }
    }
}

struct SettingListGroupRow: View {
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
    // centerSlider 自带标题行 + 轨道 + 标点,内部已有纵向结构,外层只需较紧的
    // 留白;cardSelection 等仍用标准 lg 留白。
    private var embeddedVerticalPadding: CGFloat {
        switch embeddedControl {
        case .centerSlider?, .rangeSlider?:
            return DesignTokens.Spacing.sm
        default:
            return DesignTokens.Spacing.lg
        }
    }
    private var usesRowHover: Bool { !isEmbeddedOnly }
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
            accessibilityValue: isExpandable ? (isExpanded ? "Expanded" : "Collapsed") : "",
            action: handleTap
        ) { _ in
            rowSurfaceContent
        }
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
        // Drives the height change of this row and the rows it pushes down with
        // the same bouncy spring the detail panel animates in on.
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

    @ViewBuilder
    private var trailingAccessory: some View {
        switch accessory {
        case .none:
            EmptyView()

        case .automatic:
            Image(systemName: "chevron.right")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                // Expandable rows rotate the chevron to point down when open;
                // plain navigation rows keep it static as a forward affordance.
                .rotationEffect(isExpandable && isExpanded ? .degrees(90) : .zero)

        case .menu(let title, let options, let role):
            Menu {
                if options.isEmpty {
                    Text("No Options")
                } else {
                    ForEach(options) { option in
                        Button(option.title, role: option.role) {
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
            .accessibilityLabel(title)

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

    /// The disclosure motion: a small anchored scale
    /// plus opacity and an edge slide on insertion, fading out on removal. The
    /// anchor/edge follow `expansion`, so top rows grow down, bottom rows grow
    /// up, and middle rows scale out from their centre.
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

struct SettingListGroupDivider: View {
    var body: some View {
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

    // CenterSlider 两侧各有一个图标列(Interactive.compact)与一段 spacing(md),
    // 轨道宽 = 行宽 - 左右 padding(lg×2) - 两图标列 - 两段 spacing。据此让轨道
    // 撑满到与 HDR 行相同的左右边距;detentDots / 旋钮按 trackWidth 自动延展。
    private var resolvedTrackWidth: CGFloat {
        let sidePadding = DesignTokens.Spacing.lg * 2
        let iconColumns = DesignTokens.Interactive.compact * 2
        let spacings = DesignTokens.Spacing.md * 2
        return max(rowWidth - sidePadding - iconColumns - spacings, 200)
    }

    var body: some View {
        // 标题不再占据左侧固定列,而是浮在滑轨正上方、注视时淡入。这一行始终
        // 预留一行标题高度,避免淡入/淡出时把滑块顶上顶下。
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

/// Embedded-control row for `EmbeddedControl.rangeSlider`. Mirrors
/// `SettingListCenterSliderRow`'s gaze-revealed title + full-width track
/// resolution, but pairs the track with a numeric readout and uses the
/// leading-origin continuous `RangeSlider` instead of the detented centre slider.
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

    // Same track-width arithmetic as the centre slider row so both fill to an
    // identical inset; the range slider has no end-icon columns, so it only
    // subtracts the side padding.
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
                .glassBackgroundEffect(in: Circle())
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
                Image(systemName: systemName)
                    .font(DesignTokens.Typography.sectionHeader)
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
        .background(DesignTokens.Surface.elevated, in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .contentShape(.interaction, Capsule())
        .animation(DesignTokens.AnimationToken.selection, value: title)
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
        .accessibilityLabel(accessibilityLabel)
    }
}

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

enum PlaybackTopSecondaryMenu: String {
    case dock
    case videoFormat
}

struct PlaybackTopActions: View {
    private let canDock: Bool
    private let canApplyFormat: Bool
    private let onDock: ((SpatialSceneDomain.CinemaEnvironment) -> Void)?
    private let onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)?

    @State private var presentedMenu: PlaybackTopSecondaryMenu?
    @State private var selectedEnvironment: SpatialSceneDomain.CinemaEnvironment = .darkTheatre
    @State private var projection: PlaybackModel.ProjectionType = .flat
    @State private var stereoLayout: PlaybackModel.StereoLayout = .mono

    init(
        initialPresentedMenu: PlaybackTopSecondaryMenu? = nil,
        canDock: Bool = true,
        canApplyFormat: Bool = true,
        onDock: ((SpatialSceneDomain.CinemaEnvironment) -> Void)? = nil,
        onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)? = nil
    ) {
        self.canDock = canDock
        self.canApplyFormat = canApplyFormat
        self.onDock = onDock
        self.onApplyFormat = onApplyFormat
        _presentedMenu = State(initialValue: initialPresentedMenu)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            topActionButton(
                title: "Dock",
                systemName: "square.stack.3d.up",
                menu: .dock,
                isEnabled: canDock
            )

            topActionButton(
                title: "Video Format",
                systemName: "pano",
                menu: .videoFormat,
                isEnabled: canApplyFormat
            )
        }
        .overlay(alignment: .topTrailing) {
            Group {
                switch presentedMenu {
                case .dock: dockMenu
                case .videoFormat: videoFormatMenu
                case nil: EmptyView()
                }
            }
            .offset(y: DesignTokens.Interactive.large)
            .zIndex(10)
        }
        .onChange(of: canDock) { _, available in
            if available == false, presentedMenu == .dock { presentedMenu = nil }
        }
        .onChange(of: canApplyFormat) { _, available in
            if available == false, presentedMenu == .videoFormat { presentedMenu = nil }
        }
    }

    private func topActionButton(
        title: String,
        systemName: String,
        menu: PlaybackTopSecondaryMenu,
        isEnabled: Bool
    ) -> some View {
        Button {
            presentedMenu = presentedMenu == menu ? nil : menu
        } label: {
            Label(title, systemImage: systemName)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(isEnabled ? .white : .secondary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minHeight: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .frame(minHeight: DesignTokens.Interactive.large)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier("PlayerUI-TopAction-\(menu.rawValue)")
    }

    private var dockMenu: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            menuHeading("Dock", supporting: "Choose an environment")

            VStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(SpatialSceneDomain.CinemaEnvironment.allCases, id: \.self) { environment in
                    Button {
                        selectedEnvironment = environment
                        presentedMenu = nil
                        onDock?(environment)
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: environmentIcon(environment))
                                .frame(width: DesignTokens.Interactive.regular)

                            Text(environmentTitle(environment))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedEnvironment == environment {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(DesignTokens.Typography.metadata)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .frame(minHeight: DesignTokens.Interactive.large)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .enchronHoverEffect(.highlight)
                    .accessibilityIdentifier("PlayerUI-DockMenu-\(environment.rawValue)")
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    private var videoFormatMenu: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            menuHeading("Video Format", supporting: "Choose how the video is presented")

            formatPicker(
                title: "Projection",
                selection: $projection,
                options: [
                    PlaybackModel.ProjectionType.flat,
                    .equirectangular180,
                    .equirectangular360,
                    .fisheye
                ],
                label: projectionTitle
            )

            formatPicker(
                title: "Stereo Layout",
                selection: $stereoLayout,
                options: PlaybackModel.StereoLayout.allCases,
                label: stereoTitle
            )

            HStack {
                Spacer()
                Button("Cancel") {
                    presentedMenu = nil
                }
                .accessibilityIdentifier("PlayerUI-VideoFormat-cancel")
                Button("Apply") {
                    presentedMenu = nil
                    onApplyFormat?(projection, stereoLayout)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("PlayerUI-VideoFormat-apply")
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    private func menuHeading(_ title: String, supporting: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.headline)
            Text(supporting)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func formatPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                        .accessibilityIdentifier("PlayerUI-VideoFormat-\(title)-\(label(option))")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    private func environmentTitle(_ environment: SpatialSceneDomain.CinemaEnvironment) -> String {
        switch environment {
        case .darkTheatre: "Dark Theatre"
        case .starryNight: "Starry Night"
        case .sunsetNature: "Sunset Nature"
        }
    }

    private func environmentIcon(_ environment: SpatialSceneDomain.CinemaEnvironment) -> String {
        switch environment {
        case .darkTheatre: "theatermasks"
        case .starryNight: "sparkles"
        case .sunsetNature: "sun.horizon"
        }
    }

    private func projectionTitle(_ projection: PlaybackModel.ProjectionType) -> String {
        switch projection {
        case .flat: "Flat"
        case .equirectangular180: "180°"
        case .equirectangular360: "360°"
        case .fisheye: "Fisheye"
        }
    }

    private func stereoTitle(_ stereoLayout: PlaybackModel.StereoLayout) -> String {
        switch stereoLayout {
        case .mono: "Mono"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }
}

struct NavBackForwardCapsuleControl: View {
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var accessibilityIdentifier: String = "DesignPreview-control-navBackForward"
    var accessibilityLabel: String = "Back and Forward"

    // 锁死:图标恒白、forward 半区恒 0.65 透明,不暴露。
    private let iconColor: Color = .white
    private let trailingOpacity: Double = 0.65

    @State private var pressedSide: NavSide? = nil
    @State private var pressFeedbackTrigger = 0

    private enum NavSide { case back, forward }

    var body: some View {
        let capsuleWidth = DesignTokens.Interactive.regular * 2
        let press = DesignTokens.PressFeedback.icon

        ZStack {
            HStack(spacing: 0) {
                Image(systemName: "chevron.left")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(iconColor)
                    .scaleEffect(pressedSide == .back ? press.pressedScale : 1.0)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                Image(systemName: "chevron.right")
                    .font(DesignTokens.SymbolSize.control)
                    .foregroundStyle(iconColor.opacity(trailingOpacity))
                    .scaleEffect(pressedSide == .forward ? press.pressedScale : 1.0)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
            }
            .frame(width: capsuleWidth, height: DesignTokens.Interactive.regular)
            .enchronGlassControl()
        }
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                let tapped: NavSide = value.location.x < capsuleWidth / 2 ? .back : .forward
                pressFeedbackTrigger += 1
                withAnimation(press.pressAnimation) { pressedSide = tapped }
                Task {
                    try? await Task.sleep(for: press.holdDuration)
                    withAnimation(press.releaseAnimation) { pressedSide = nil }
                }
                if tapped == .back { onBack() } else { onForward() }
            }
        )
        .sensoryFeedback(.press(.buttonIconOnly), trigger: pressFeedbackTrigger)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap left half for back, right half for forward")
    }
}

struct ViewModeCapsuleControl: View {
    @Binding var selection: Int
    var accessibilityIdentifier: String = "DesignPreview-control-viewMode"
    var accessibilityLabel: String = "View Mode"

    // 锁死:图标恒白、未选透明度 0.45,不暴露给调用点。
    private let iconColor: Color = .white
    private let unselectedOpacity: Double = 0.45

    @Namespace private var indicatorNamespace
    @State private var pressedIndex: Int? = nil
    @State private var pressFeedbackTrigger = 0

    var body: some View {
        let capsuleWidth = DesignTokens.Interactive.regular * 2
        let press = DesignTokens.PressFeedback.icon

        ZStack {
            HStack(spacing: 0) {
                viewModeIcon("square.grid.2x2", isSelected: selection == 0, isPressed: pressedIndex == 0)
                viewModeIcon("list.bullet", isSelected: selection == 1, isPressed: pressedIndex == 1)
            }
            .frame(width: capsuleWidth, height: DesignTokens.Interactive.regular)
            .enchronGlassControl()
        }
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                let tapped = value.location.x < capsuleWidth / 2 ? 0 : 1
                pressFeedbackTrigger += 1
                withAnimation(press.pressAnimation) { pressedIndex = tapped }
                Task {
                    try? await Task.sleep(for: press.holdDuration)
                    withAnimation(DesignTokens.AnimationToken.selection) {
                        selection = tapped
                        pressedIndex = nil
                    }
                }
            }
        )
        .sensoryFeedback(.press(.buttonIconOnly), trigger: pressFeedbackTrigger)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap left half for grid, right half for list")
    }

    @ViewBuilder
    private func viewModeIcon(_ icon: String, isSelected: Bool, isPressed: Bool) -> some View {
        let press = DesignTokens.PressFeedback.icon

        ZStack {
            if isSelected {
                Circle()
                    .fill(DesignTokens.Surface.selected)
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                    .matchedGeometryEffect(id: "viewModeIndicator", in: indicatorNamespace)
            }

            Image(systemName: icon)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(isSelected ? iconColor : iconColor.opacity(unselectedOpacity))
                .scaleEffect(isPressed ? press.pressedScale : 1.0)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
    }
}

// MARK: - Cards

/// 文件浏览网格里的一张卡:玻璃缩略图 + 标题,悬停浮出补充信息。
/// 视频与文件夹是同一张卡的两个变体,经 `GridCard.video(...)` / `GridCard.folder(...)` 构造。
/// 宽高、缩略图、玻璃、悬停动画、按压反馈全部锁死(token 驱动),组装时只填数据。
struct GridCard: View {
    /// 变体轴:决定缩略图内容与悬停信息布局。缩略图内容由变体内部钉死,不开放给调用点。
    enum Variant {
        case video(fileSize: String, duration: String, badges: [String], watchedProgress: Double?)
        case folder(count: Int)
    }

    @Namespace private var hoverNamespace

    private let title: String
    private let variant: Variant
    private let explicitIdentifier: String?
    /// When set, the whole card is a real interactive control (same contract as
    /// `FileListGroup.Item.action`). When `nil`, the card is display-only — used
    /// by showcase previews. This is what unifies grid and list interaction:
    /// both drive the same routing instead of the grid bolting on an external
    /// `.onTapGesture`, which hit-tested unreliably over the card's own gestures.
    private let action: (() -> Void)?

    private init(title: String, variant: Variant, identifier: String?, action: (() -> Void)?) {
        self.title = title
        self.variant = variant
        self.explicitIdentifier = identifier
        self.action = action
    }

    // MARK: 变体工厂

    static func video(
        title: String,
        fileSize: String,
        duration: String,
        badges: [String] = [],
        /// 0…1 已观看进度;`nil` 表示未看过(不画底部进度描边)。
        watchedProgress: Double? = nil,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(
            title: title,
            variant: .video(
                fileSize: fileSize,
                duration: duration,
                badges: badges,
                watchedProgress: watchedProgress
            ),
            identifier: accessibilityIdentifier,
            action: action
        )
    }

    static func folder(
        title: String,
        count: Int,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) -> GridCard {
        GridCard(title: title, variant: .folder(count: count), identifier: accessibilityIdentifier, action: action)
    }

    // MARK: 无障碍派生

    private var variantKey: String {
        switch variant {
        case .video: return "video"
        case .folder: return "folder"
        }
    }

    private var resolvedIdentifier: String {
        explicitIdentifier ?? "grid-card-\(variantKey)-\(title)"
    }

    private var resolvedLabel: String {
        "\(title), \(variantKey)"
    }

    // MARK: 悬停组(@Namespace 按实例隔离,id 字面量可复用)

    private var hoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "grid-card-thumbnail-info", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var hoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "grid-card-thumbnail-info", in: hoverNamespace, behavior: .followsGroup)
    }

    var body: some View {
        if let action {
            cardVisual
                .onTapGesture(perform: action)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(resolvedIdentifier)
                .accessibilityLabel(resolvedLabel)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { action() }
        } else {
            cardVisual
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier(resolvedIdentifier)
                .accessibilityLabel(resolvedLabel)
                .accessibilityAddTraits(.isButton)
        }
    }

    private var cardVisual: some View {
        let shape = DesignTokens.ShapeToken.card
        return VStack(alignment: .leading, spacing: 0) {
            thumbnailContent(shape)
                .frame(height: DesignTokens.Card.thumbnailHeight)
                .clipShape(shape)
                .glassBackgroundEffect(in: shape)
                .enchronHoverContentShape(shape)
                .enchronHoverEffect(.highlight, in: hoverActivationGroup)

            Text(title)
                .font(DesignTokens.Typography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Card.paddingH)
                .padding(.vertical, DesignTokens.Card.paddingV)
        }
        .frame(width: DesignTokens.Card.gridMin)
        .contentShape(shape)
    }

    @ViewBuilder
    private func thumbnailContent(_ shape: RoundedRectangle) -> some View {
        switch variant {
        case let .video(fileSize, duration, badges, watchedProgress):
            // 缩略图占位 — 真实 app 中为视频帧/海报
            shape.fill(DesignTokens.Surface.elevated)
                .overlay(alignment: .center) {
                    thumbnailPlaceholderIcon("film")
                }
                .overlay {
                    videoThumbnailInfo(fileSize: fileSize, duration: duration, badges: badges)
                }
                .overlay {
                    if let watchedProgress {
                        watchedProgressBar(watchedProgress)
                    }
                }
        case let .folder(count):
            shape.fill(DesignTokens.Surface.elevated)
                .overlay(alignment: .center) {
                    thumbnailPlaceholderIcon("folder.fill")
                }
                .overlay(alignment: .bottomLeading) {
                    folderThumbnailInfo(count: count)
                }
        }
    }

    private func videoThumbnailInfo(fileSize: String, duration: String, badges: [String]) -> some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                if !badges.isEmpty {
                    HStack(spacing: DesignTokens.Spacing.xxs) {
                        ForEach(badges, id: \.self) { badge in
                            thumbnailBadge(badge)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                thumbnailMetadata(fileSize)
                Spacer()
                thumbnailMetadata(duration)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .enchronHoverOpacity(
            active: 1,
            inactive: 0,
            in: hoverRevealGroup,
            animation: DesignTokens.AnimationToken.controlsTransition
        )
        .allowsHitTesting(false)
    }

    private func folderThumbnailInfo(count: Int) -> some View {
        HStack {
            thumbnailMetadata("\(count) items")
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .enchronHoverOpacity(
            active: 1,
            inactive: 0,
            in: hoverRevealGroup,
            animation: DesignTokens.AnimationToken.controlsTransition
        )
        .allowsHitTesting(false)
    }

    private func thumbnailBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .foregroundStyle(DesignTokens.Surface.supportingText)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .enchronGlassBadge()
    }

    // 底部已观看进度描边(UC-FILE-26)。嵌入卡片底边:thin 描边随缩略图 clipShape 贴合圆角,
    // 仅 hover 时随缩略图 hover 组显隐;未 hover 不显示。视觉本体见 `watchedEdgeProgressVisual`。
    private func watchedProgressBar(_ progress: Double) -> some View {
        watchedEdgeProgressVisual(progress)
            .enchronHoverOpacity(
                active: 1,
                inactive: 0,
                in: hoverRevealGroup,
                animation: DesignTokens.AnimationToken.controlsTransition
            )
    }

    // 居中占位图标:无缩略图时的视频/文件夹标识。视频与文件夹共用同一尺寸与前景色,避免分叉。
    private func thumbnailPlaceholderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: DesignTokens.Card.placeholderIconSize))
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }

    // 元数据与占位图标统一用 Surface.supportingText(token);视频与文件夹一致。
    private func thumbnailMetadata(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(DesignTokens.Surface.supportingText)
    }
}

// 已观看进度描边的纯视觉本体(无 hover 门控):把卡片当作【直角矩形】画满整条底边
// (全宽,贴底,高 = watchedEdgeHeight 的 `Theme.accent` 细线),圆角交给卡片的
// `clipShape` 收口——超出圆角的部分被系统自动裁掉,描边两端顺圆角自然收尾。
// 进度从左铺,width = 全宽 × progress,100% 占满整条底边。无未看段 track。
// 整体填满卡片尺寸,作 `.overlay { }` 叠在缩略图上(clipShape 在 overlay 之后,故会裁)。
func watchedEdgeProgressVisual(_ progress: Double) -> some View {
    let clamped = max(0, min(1, progress))
    let lineWidth = DesignTokens.ProgressBar.watchedEdgeHeight
    return GeometryReader { proxy in
        Rectangle()
            .fill(DesignTokens.Theme.accent)
            .frame(width: proxy.size.width * clamped, height: lineWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            // 自己按卡片圆角 clip:全宽直线在圆角处被弧线切掉,两端顺圆角收口,不外溢。
            .clipShape(DesignTokens.ShapeToken.card)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
}

// 演示:呈现 hover 显示后的底边进度描边,25% / 50% / 100% 三态。
// 静态渲染触发不了 gaze hover,这里直接用视觉本体常显,等价于卡片 hover 后的样子。
private struct WatchedEdgeProgressDemo: View {
    private let shape = DesignTokens.ShapeToken.card
    private let samples: [Double] = [0.25, 0.5, 1.0]

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xl) {
            ForEach(samples, id: \.self) { p in
                VStack(spacing: DesignTokens.Spacing.sm) {
                    shape.fill(DesignTokens.Surface.elevated)
                        .overlay(alignment: .center) {
                            Image(systemName: "film")
                                .font(.system(size: DesignTokens.Card.placeholderIconSize))
                                .foregroundStyle(DesignTokens.Surface.supportingText)
                        }
                        .overlay { watchedEdgeProgressVisual(p) }
                        .frame(width: DesignTokens.Card.gridMin, height: DesignTokens.Card.thumbnailHeight)
                        .clipShape(shape)
                        .glassBackgroundEffect(in: shape)

                    Text("\(Int(p * 100))%")
                        .font(DesignTokens.Typography.metadata)
                        .foregroundStyle(DesignTokens.Surface.supportingText)
                }
            }
        }
        .padding(DesignTokens.Spacing.xxxl)
    }
}

#Preview("Watched edge · 25/50/100") {
    WatchedEdgeProgressDemo()
}

struct FeaturedEnvironment: Identifiable {
    let environment: SpatialSceneDomain.CinemaEnvironment
    let imageName: String
    let title: String
    let environmentNumber: String
    let quote: String
    let mode: String
    let atmosphere: String

    var id: String { environment.rawValue }

    static let catalog: [FeaturedEnvironment] = [
        .init(
            environment: .darkTheatre,
            imageName: "SceneFeatureCinema",
            title: "Dark Theatre",
            environmentNumber: "Environment 01",
            quote: "\"A focused private theatre with the world held outside.\"",
            mode: "Classic theatre",
            atmosphere: "Dark / quiet"
        ),
        .init(
            environment: .starryNight,
            imageName: "SceneFeatureOrbitalGarden",
            title: "Starry Night",
            environmentNumber: "Environment 02",
            quote: "\"A quiet screen beneath an open night sky.\"",
            mode: "Open-air cinema",
            atmosphere: "Night / starlight"
        ),
        .init(
            environment: .sunsetNature,
            imageName: "SceneFeatureDesert",
            title: "Sunset Nature",
            environmentNumber: "Environment 03",
            quote: "\"Warm horizon light surrounds a calm viewing space.\"",
            mode: "Nature cinema",
            atmosphere: "Sunset / warm air"
        )
    ]
}

struct EnvironmentCard: View {
    var environment: FeaturedEnvironment = .catalog[0]
    var detailVisibility: CGFloat = 1
    var atmosphericFade: CGFloat = 0
    var onReturn: () -> Void = {}
    var onExpand: () -> Void = {}
    var onMore: () -> Void = {}

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: Metrics.cornerRadius,
            style: .continuous
        )

        ZStack(alignment: .bottom) {
            backgroundImage
            topMultiplyOverlay
            environmentInfoPanel
            topControls
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        .overlay {
            shape.strokeBorder(DesignTokens.Surface.overlay, lineWidth: DesignTokens.Stroke.regular)
        }
        .enchronHoverContentShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DesignPreview-EnvironmentCard")
        .accessibilityLabel("Featured environment card, \(environment.title)")
    }

    private var clampedDetailVisibility: CGFloat {
        max(0, min(1, detailVisibility))
    }

    private var clampedAtmosphericFade: CGFloat {
        max(0, min(1, atmosphericFade))
    }

    private var backgroundImage: some View {
        Image(environment.imageName)
            .resizable()
            .scaledToFill()
            .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
            .saturation(Double(1 - clampedAtmosphericFade * Metrics.atmosphericDesaturation))
            .contrast(Double(1 - clampedAtmosphericFade * Metrics.atmosphericContrastReduction))
            .blur(radius: clampedAtmosphericFade * Metrics.atmosphericBlurRadius)
            .clipped()
    }

    private var topControls: some View {
        VStack {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GlassCircleIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Return to window",
                    action: onReturn,
                    accessibilityIdentifier: "DesignPreview-EnvironmentCard-button-return"
                )
                Spacer()
                GlassCircleIconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: "Expand environment",
                    action: onExpand,
                    accessibilityIdentifier: "DesignPreview-EnvironmentCard-button-expand"
                )
            }
            .padding(Metrics.chromePadding)
            Spacer()
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .opacity(Double(clampedDetailVisibility))
    }

    private var topMultiplyOverlay: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black)
                .blendMode(.multiply)
                .mask(topMultiplyFadeMask)
                .frame(height: Metrics.topMultiplyHeight)
            Spacer(minLength: 0)
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .opacity(Double(clampedDetailVisibility))
    }

    private var environmentInfoPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(environment.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)
                Spacer(minLength: DesignTokens.Spacing.md)
                Text(environment.environmentNumber)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(environment.quote)
                .font(.title3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Mode: \(environment.mode)")
                Text("Atmosphere: \(environment.atmosphere)")
            }
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, Metrics.infoPaddingH)
        .padding(.top, Metrics.infoPaddingTop)
        .padding(.bottom, Metrics.infoPaddingBottom)
        .frame(width: Metrics.cardWidth,
               height: Metrics.infoHeight,
               alignment: .topLeading)
        .background {
            Rectangle()
                .fill(Color.black)
                .blendMode(.multiply)
                .mask(infoMaterialFadeMask)
        }
        .opacity(Double(clampedDetailVisibility))
    }

    private var infoMaterialFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(Metrics.infoFadeMinOpacity), location: 0),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.34), location: 0.08),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.52), location: 0.18),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.62), location: 0.42),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.72), location: 0.68),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity * 0.92), location: 0.88),
                .init(color: .white.opacity(Metrics.infoFadeMaxOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topMultiplyFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(Metrics.topFadeMaxOpacity), location: 0),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private enum Metrics {
        static let cardWidth: CGFloat = 500
        static let cardHeight: CGFloat = 548
        static let infoHeight: CGFloat = 188
        static let cornerRadius: CGFloat = DesignTokens.Radius.card
        static let chromePadding: CGFloat = 18
        static let infoPaddingH: CGFloat = 36
        static let infoPaddingTop: CGFloat = 34
        static let infoPaddingBottom: CGFloat = 14
        static let infoFadeMinOpacity: CGFloat = 0
        static let infoFadeMaxOpacity: CGFloat = 0.45
        static let topMultiplyHeight: CGFloat = 160
        static let topFadeMaxOpacity: CGFloat = 0.40
        static let atmosphericContrastReduction: CGFloat = 0.68
        static let atmosphericDesaturation: CGFloat = 0.38
        static let atmosphericBlurRadius: CGFloat = 2.6
    }
}

struct EnvironmentCardCarousel: View {
    var environments: [FeaturedEnvironment] = FeaturedEnvironment.catalog
    var onReturn: () -> Void = {}
    /// Center-card expand (enter immersive). Forwarded from the focused card's
    /// expand control; defaults to no-op for Canvas review (ENV-18).
    var onExpand: (FeaturedEnvironment) -> Void = { _ in }

    @State private var scrollPosition: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var isSettling = false
    @State private var detailsVisible = true
    @State private var motionGeneration = 0
    @State private var detailRevealTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if environments.isEmpty {
                EmptyView()
            } else {
                ForEach(renderItems) { item in
                    EnvironmentCard(
                        environment: item.environment,
                        detailVisibility: interactionDetailVisibility(for: item.visualPosition),
                        atmosphericFade: atmosphericFade(for: item.visualPosition),
                        onReturn: onReturn,
                        onExpand: { onExpand(item.environment) },
                        onMore: {}
                    )
                    .allowsHitTesting(abs(item.visualPosition) < Metrics.centerHitTestingDistance)
                    .opacity(Double(cardOpacity(for: item.visualPosition)))
                    .enchronSpatialOffset(z: zOffset(for: item.visualPosition))
                    .offset(x: xOffset(for: item.visualPosition), y: yOffset(for: item.visualPosition))
                    .zIndex(zIndex(for: item.visualPosition))
                    .accessibilityHidden(abs(item.visualPosition) >= Metrics.centerHitTestingDistance)
                }
            }
        }
        .frame(width: Metrics.stageWidth, height: Metrics.stageHeight)
        .enchronSpatialFrame(depth: Metrics.stageDepth)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityIdentifier("DesignPreview-EnvironmentCardCarousel")
    }

    private var renderItems: [RenderItem] {
        environments.indices.compactMap { index in
            let visualPosition = visualPosition(for: index)
            guard abs(visualPosition) <= activeRenderCardDistance else {
                return nil
            }

            return RenderItem(
                visualPosition: visualPosition,
                environment: environments[index]
            )
        }
    }

    private var activeRenderCardDistance: CGFloat {
        isDragging || isSettling ? Metrics.motionRenderCardDistance : Metrics.stableRenderCardDistance
    }

    private var currentScrollPosition: CGFloat {
        guard !environments.isEmpty else { return 0 }
        let gestureProgress = -dragTranslation / Metrics.dragDistance
        return scrollPosition + gestureProgress
    }

    private var interactionDetailScale: CGFloat {
        detailsVisible && !isDragging ? 1 : 0
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                if !isDragging {
                    motionGeneration += 1
                    detailRevealTask?.cancel()
                    isDragging = true
                    isSettling = false
                    detailsVisible = false
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let actualProgress = -value.translation.width / Metrics.dragDistance
                let projectedProgress = -value.predictedEndTranslation.width / Metrics.dragDistance
                let actualPosition = scrollPosition + actualProgress
                let projectedPosition = scrollPosition + projectedProgress
                let targetPosition = targetScrollPosition(
                    actualPosition: actualPosition,
                    projectedPosition: projectedPosition
                )
                let targetStepDistance = abs(targetPosition - scrollPosition)
                let generation = motionGeneration

                isDragging = false
                isSettling = true
                scheduleDetailReveal(for: generation, stepDistance: targetStepDistance)
                withAnimation(
                    DesignTokens.AnimationToken.sceneCarouselSettle,
                    completionCriteria: .logicallyComplete
                ) {
                    dragTranslation = 0
                    scrollPosition = targetPosition
                } completion: {
                    guard generation == motionGeneration else {
                        return
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollPosition = normalizedScrollPosition(targetPosition)
                        isSettling = false
                    }
                }
            }
    }

    private func scheduleDetailReveal(for generation: Int, stepDistance: CGFloat) {
        detailRevealTask?.cancel()
        detailRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: detailRevealDelay(for: stepDistance))
            guard !Task.isCancelled,
                  generation == motionGeneration,
                  !isDragging
            else {
                return
            }

            withAnimation(DesignTokens.AnimationToken.fadeIn) {
                detailsVisible = true
            }
        }
    }

    private func detailRevealDelay(for stepDistance: CGFloat) -> UInt64 {
        Metrics.detailRevealDelayNanoseconds
            + UInt64(max(0, stepDistance.rounded(.down))) * Metrics.detailRevealDelayPerStepNanoseconds
    }

    private func visualPosition(for index: Int) -> CGFloat {
        guard !environments.isEmpty else { return 0 }
        let environmentCount = CGFloat(environments.count)
        let rawPosition = CGFloat(index) - currentScrollPosition
        return rawPosition - (rawPosition / environmentCount).rounded() * environmentCount
    }

    private func normalizedScrollPosition(_ position: CGFloat) -> CGFloat {
        guard !environments.isEmpty else { return 0 }
        let environmentCount = CGFloat(environments.count)
        let remainder = position.truncatingRemainder(dividingBy: environmentCount)
        return remainder >= 0 ? remainder : remainder + environmentCount
    }

    private func targetScrollPosition(actualPosition: CGFloat, projectedPosition: CGFloat) -> CGFloat {
        let actualDelta = actualPosition - scrollPosition
        let rawProjectedDelta = projectedPosition - scrollPosition
        let projectedDelta = clamped(
            rawProjectedDelta,
            lowerBound: actualDelta - Metrics.maximumPredictedStepLead,
            upperBound: actualDelta + Metrics.maximumPredictedStepLead
        )
        let dominantDelta = abs(projectedDelta) > abs(actualDelta) ? projectedDelta : actualDelta
        let boundedDelta = clamped(
            dominantDelta,
            lowerBound: -Metrics.maximumStepPerGesture,
            upperBound: Metrics.maximumStepPerGesture
        )
        let roundedDelta = boundedDelta.rounded()

        if roundedDelta == 0, abs(boundedDelta) > Metrics.snapThreshold {
            return scrollPosition + (boundedDelta > 0 ? 1 : -1)
        }

        return scrollPosition + roundedDelta
    }

    private func clamped(_ value: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        max(lowerBound, min(upperBound, value))
    }

    private func xOffset(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        let sign: CGFloat = position < 0 ? -1 : 1
        let baseOffset = distance <= 1
            ? distance * Metrics.centerCardGap
            : Metrics.centerCardGap + (distance - 1) * Metrics.outerCardGap
        return sign * (baseOffset + edgeExitProgress(for: distance) * Metrics.edgeSlideOutDistance)
    }

    private func yOffset(for position: CGFloat) -> CGFloat {
        abs(position) * Metrics.sideCardYOffset
    }

    private func zOffset(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        let baseOffset = Metrics.centerDepthOffset - distance * Metrics.sideDepthOffset
        let edgeExitOffset = edgeExitProgress(for: distance) * Metrics.edgeDepthRetreat
        return baseOffset - edgeExitOffset
    }

    private func cardOpacity(for position: CGFloat) -> CGFloat {
        let distance = abs(position)

        if distance <= Metrics.fullOpacityDistance {
            return 1
        } else if distance <= Metrics.firstSideOpacityDistance {
            return interpolatedOpacity(
                from: 1,
                to: Metrics.firstSideOpacity,
                distance: distance,
                start: Metrics.fullOpacityDistance,
                end: Metrics.firstSideOpacityDistance
            )
        } else if distance <= Metrics.fullFadeDistance {
            return interpolatedOpacity(
                from: Metrics.firstSideOpacity,
                to: 0,
                distance: distance,
                start: Metrics.firstSideOpacityDistance,
                end: Metrics.fullFadeDistance
            )
        }

        return 0
    }

    private func interpolatedOpacity(
        from startOpacity: CGFloat,
        to endOpacity: CGFloat,
        distance: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGFloat {
        let range = end - start
        guard range > 0 else { return endOpacity }
        let progress = clamped((distance - start) / range, lowerBound: 0, upperBound: 1)
        let easedProgress = progress * progress * (3 - 2 * progress)
        return startOpacity + (endOpacity - startOpacity) * easedProgress
    }

    private func interactionDetailVisibility(for position: CGFloat) -> CGFloat {
        detailVisibility(for: position) * interactionDetailScale
    }

    private func detailVisibility(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        guard distance < Metrics.detailRevealStart else { return 0 }

        let revealRange = Metrics.detailRevealStart - Metrics.detailRevealComplete
        guard revealRange > 0 else { return 1 }

        return max(0, min(1, (Metrics.detailRevealStart - distance) / revealRange))
    }

    private func atmosphericFade(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        guard distance > Metrics.atmosphericFadeStart else { return 0 }

        let fadeRange = Metrics.atmosphericFadeEnd - Metrics.atmosphericFadeStart
        guard fadeRange > 0 else { return Metrics.atmosphericFadeMaxOpacity }

        let progress = max(0, min(1, (distance - Metrics.atmosphericFadeStart) / fadeRange))
        let edgeBoost = edgeExitProgress(for: distance) * Metrics.edgeAtmosphericBoost
        return min(1, progress * Metrics.atmosphericFadeMaxOpacity + edgeBoost)
    }

    private func edgeExitProgress(for distance: CGFloat) -> CGFloat {
        guard distance > Metrics.edgeExitStart else { return 0 }

        let exitRange = Metrics.edgeExitEnd - Metrics.edgeExitStart
        guard exitRange > 0 else { return 1 }

        let rawProgress = max(0, min(1, (distance - Metrics.edgeExitStart) / exitRange))
        return rawProgress * rawProgress
    }

    private func zIndex(for position: CGFloat) -> Double {
        100 - Double(abs(position) * 10)
    }

    private enum Metrics {
        static let stageWidth: CGFloat = DesignTokens.EnvironmentCarousel.stageWidth
        static let stageHeight: CGFloat = DesignTokens.EnvironmentCarousel.stageHeight
        static let stageDepth: CGFloat = DesignTokens.EnvironmentCarousel.stageDepth
        static let dragDistance: CGFloat = DesignTokens.EnvironmentCarousel.dragDistance
        static let snapThreshold: CGFloat = DesignTokens.EnvironmentCarousel.snapThreshold
        static let maximumPredictedStepLead: CGFloat = DesignTokens.EnvironmentCarousel.maximumPredictedStepLead
        static let maximumStepPerGesture: CGFloat = DesignTokens.EnvironmentCarousel.maximumStepPerGesture
        static let detailRevealDelayNanoseconds = DesignTokens.EnvironmentCarousel.detailRevealDelayNanoseconds
        static let detailRevealDelayPerStepNanoseconds =
            DesignTokens.EnvironmentCarousel.detailRevealDelayPerStepNanoseconds
        static let centerHitTestingDistance: CGFloat = 0.12
        static let stableRenderCardDistance: CGFloat = 1.55
        static let motionRenderCardDistance: CGFloat = 2.18
        static let fullOpacityDistance: CGFloat = 0.10
        static let firstSideOpacityDistance: CGFloat = 1.00
        static let fullFadeDistance: CGFloat = 2.18
        static let firstSideOpacity: CGFloat = 0.85
        static let edgeExitStart: CGFloat = 1.35
        static let edgeExitEnd: CGFloat = 2.18
        static let edgeSlideOutDistance: CGFloat = 300
        static let edgeDepthRetreat: CGFloat = 42
        static let edgeAtmosphericBoost: CGFloat = 0.42
        static let centerCardGap: CGFloat = DesignTokens.EnvironmentCarousel.centerCardGap
        static let outerCardGap: CGFloat = DesignTokens.EnvironmentCarousel.outerCardGap
        static let sideCardYOffset: CGFloat = DesignTokens.EnvironmentCarousel.sideCardYOffset
        static let centerDepthOffset: CGFloat = DesignTokens.EnvironmentCarousel.centerDepthOffset
        static let sideDepthOffset: CGFloat = DesignTokens.EnvironmentCarousel.sideDepthOffset
        static let atmosphericFadeStart: CGFloat = DesignTokens.EnvironmentCarousel.atmosphericFadeStart
        static let atmosphericFadeEnd: CGFloat = DesignTokens.EnvironmentCarousel.atmosphericFadeEnd
        static let atmosphericFadeMaxOpacity: CGFloat = DesignTokens.EnvironmentCarousel.atmosphericFadeMaxOpacity
        static let detailRevealStart: CGFloat = DesignTokens.EnvironmentCarousel.detailRevealStart
        static let detailRevealComplete: CGFloat = DesignTokens.EnvironmentCarousel.detailRevealComplete
    }

    private struct RenderItem: Identifiable {
        let visualPosition: CGFloat
        let environment: FeaturedEnvironment

        var id: String {
            environment.id
        }
    }
}

// MARK: - Row items

// MARK: - File List Group

/// A file-browsing list group. Shares `ListGroupRowShell`'s row chrome with
/// `SettingListGroup` (concentric gaze highlight, separator fade, whole-row
/// tap) so file browsing and settings read in one visual language. It differs
/// in content only: a leading kind icon and trailing metadata that fades in on
/// gaze. Variants are parameter presets (`.video` / `.folder`) per ADR-0001.
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

struct GlassToggle: View {
    @State var isOn: Bool

    var body: some View {
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? DesignTokens.Theme.accent : DesignTokens.Surface.elevated)
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

private struct BoundGlassToggle: View {
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        Button {
            withAnimation(DesignTokens.AnimationToken.selection) {
                isOn.toggle()
            }
        } label: {
            Capsule()
                .fill(isOn ? DesignTokens.Theme.accent : DesignTokens.Surface.elevated)
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 26, height: 26)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic, isEnabled: isEnabled)
        .padding(.vertical, (DesignTokens.Interactive.large - 30) / 2)
        .padding(.horizontal, (DesignTokens.Interactive.large - 50) / 2)
        .contentShape(Capsule())
    }
}

// MARK: - Center slider (centered, detented, bidirectional value track)

/// Keeps the end icons aligned to the *track's* centre while the detent dots
/// hang below it. Without this the enclosing HStack would centre the icons on
/// the track+dots midpoint and they'd sit too low.
private extension VerticalAlignment {
    enum TrackCenterID: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }
    static let trackCenter = VerticalAlignment(TrackCenterID.self)
}

/// A centered value track: the knob rests at the middle origin and can be
/// dragged to symmetric notches on either side (e.g. exposure −5…+5). It reuses
/// the toggle's white knob + glass capsule vocabulary; the track stays an empty
/// grey capsule (no progress-style fill), with faint detent dots below it and a
/// caller-supplied semantic icon at each end. No numeric readout — the knob
/// position and the end icons carry the meaning. Snap-to-nearest on release.
///
/// Shared glass slider visual used by `CenterSlider` (centre-origin, detented)
/// and the timeline zoom slider (leading-origin, continuous). It draws only the
/// capsule track, accent lit fill, and white knob; the caller computes the
/// knob/lit geometry and attaches the drag gesture, so both sliders render
/// identically. The accent capsule carries its own `glassBackgroundEffect` so
/// the glass rim follows the lit shape rather than reading as flat paint.
struct GlassSliderRail: View {
    let trackWidth: CGFloat
    let trackHeight: CGFloat
    let knobSize: CGFloat
    /// Knob centre offset from the track's centre.
    let knobOffsetX: CGFloat
    /// Accent lit-fill centre offset from the track's centre.
    let litCenterX: CGFloat
    /// Accent lit-fill width.
    let litWidth: CGFloat
    let litVisible: Bool
    let isDragging: Bool

    var body: some View {
        Capsule()
            .fill(DesignTokens.Surface.elevated)
            .frame(width: trackWidth, height: trackHeight)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: max(litWidth, 0), height: trackHeight)
                    .glassBackgroundEffect(in: Capsule())
                    .offset(x: litCenterX)
                    .opacity(litVisible ? 1 : 0)
            }
            .overlay(alignment: .center) {
                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .scaleEffect(isDragging ? DesignTokens.PressFeedback.control.pressedScale : 1.0)
                    .offset(x: knobOffsetX)
            }
            .clipShape(Capsule())
            .glassBackgroundEffect(in: Capsule())
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.highlight)
    }
}

/// `CenterSlider` is the macro component; a `CenterDetentSlider` specialization
/// can be split out later if a non-detented (continuous) variant is needed.
struct CenterSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = -5...5
    let leadingSystemImage: String
    let trailingSystemImage: String
    var accessibilityLabel: String = "Center slider"
    var accessibilityIdentifier: String = "DesignPreview-CenterSlider"
    var trackWidth: CGFloat = 450
    /// 拖动状态上抛给宿主行:行据此让"标题/数值 readout"在拖动期间保持可见
    /// (gaze hover 在拖动时会离开该行,单靠 hover 会让 readout 消失)。
    var onDraggingChanged: (Bool) -> Void = { _ in }

    // Value at the moment the drag began; the live snap measures the finger's
    // translation against this origin so the knob lands on whole detents only.
    @State private var dragStartValue: Int?
    @State private var isDragging = false

    // EXPLORATORY: track-bar dimensions are not yet promoted to DesignTokens.
    // Knob (26) and track height (30) mirror the existing toggle for reuse;
    // promoting these to shared tokens needs a separate human decision.
    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26
    private let dotSize: CGFloat = 4
    private let iconColumnWidth: CGFloat = DesignTokens.Interactive.compact

    private var detentCount: Int { range.count }
    private var midValue: Double { Double(range.lowerBound + range.upperBound) / 2 }
    private var travel: CGFloat { trackWidth - knobSize }
    private var spacing: CGFloat { travel / CGFloat(detentCount - 1) }

    /// Horizontal offset (from track centre) of a given detent value.
    private func offset(for detent: Double) -> CGFloat {
        CGFloat(detent - midValue) * spacing
    }

    // The knob is purely a function of the committed detent — it never sits
    // between notches. Live snapping (below) keeps `value` quantised during the
    // drag, so the knob and lit fill can never overshoot past the end value.
    private var knobOffset: CGFloat {
        offset(for: Double(value))
    }

    var body: some View {
        HStack(alignment: .trackCenter, spacing: DesignTokens.Spacing.md) {
            Image(systemName: leadingSystemImage)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .frame(width: iconColumnWidth, height: iconColumnWidth)

            // Track + dots share a column so the dots get real layout space
            // below the track. A bare `.offset` pushed them outside the bounds
            // and they never composited. The `.trackCenter` guide keeps the end
            // icons aligned to the track's centre, not the column's midpoint.
            VStack(spacing: DesignTokens.Spacing.sm) {
                track
                    .alignmentGuide(.trackCenter) { $0[VerticalAlignment.center] }
                detentDots
            }

            Image(systemName: trailingSystemImage)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
                .frame(width: iconColumnWidth, height: iconColumnWidth)
        }
        .accessibilityElement()
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + 1)
            case .decrement: setValue(value - 1)
            @unknown default: break
            }
        }
    }

    // Gesture lives on the *static* track, never on the moving knob, so the
    // drag coordinate space stays fixed and the offset can't feed back on itself
    // (the source of the earlier jitter). The accent lit-fill runs from the
    // centre origin to the knob; hidden at the origin. Visual is shared with the
    // timeline zoom slider via `GlassSliderRail`.
    private var track: some View {
        let radius = trackHeight / 2
        return GlassSliderRail(
            trackWidth: trackWidth,
            trackHeight: trackHeight,
            knobSize: knobSize,
            knobOffsetX: knobOffset,
            litCenterX: (knobOffset + (knobOffset >= 0 ? radius : -radius)) / 2,
            litWidth: abs(knobOffset) + radius,
            litVisible: abs(knobOffset) > 0.5,
            isDragging: isDragging
        )
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                let start = dragStartValue ?? value
                if dragStartValue == nil {
                    dragStartValue = start
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDragging = true
                    }
                    onDraggingChanged(true)
                }
                // Map the finger's position back to the nearest in-range detent
                // and commit it live; the knob then glides notch-to-notch with the
                // selection spring, reading as a magnetic snap rather than a free
                // slide that has to be caught on release.
                let landed = offset(for: Double(start)) + gesture.translation.width
                let proposed = clamp(Int((midValue + Double(landed / spacing)).rounded()))
                if proposed != value {
                    withAnimation(snapAnimation(to: proposed)) {
                        value = proposed
                    }
                }
            }
            .onEnded { _ in
                dragStartValue = nil
                withAnimation(DesignTokens.PressFeedback.control.releaseAnimation) {
                    isDragging = false
                }
                onDraggingChanged(false)
            }
    }

    private var detentDots: some View {
        ZStack {
            ForEach(Array(range), id: \.self) { detent in
                let isCenter = Double(detent) == midValue
                // All dots share the empty track's own tint so they read as quiet
                // anchors, never competing with the knob or the lit fill for
                // attention. The centre origin stands out only by its larger
                // size, not by a brighter colour.
                Circle()
                    .fill(DesignTokens.Surface.divider)
                    .frame(
                        width: isCenter ? dotSize + 3 : dotSize,
                        height: isCenter ? dotSize + 3 : dotSize
                    )
                    .offset(x: offset(for: Double(detent)))
            }
        }
        .frame(width: trackWidth, height: dotSize + 3)
    }

    private func clamp(_ newValue: Int) -> Int {
        min(max(newValue, range.lowerBound), range.upperBound)
    }

    // Mid-track snaps keep the bouncy `selection` spring for the magnetic Q feel;
    // snaps onto the two end detents settle without overshoot, so the bounce
    // can't drive the knob past the clipped capsule edge and spring back.
    private func snapAnimation(to detent: Int) -> Animation {
        detent == range.lowerBound || detent == range.upperBound
            ? DesignTokens.AnimationToken.sceneCarouselSettle
            : DesignTokens.AnimationToken.selection
    }

    private func setValue(_ newValue: Int) {
        let clamped = clamp(newValue)
        withAnimation(snapAnimation(to: clamped)) {
            value = clamped
        }
    }
}

/// Leading-origin continuous slider over an arbitrary `Double` range. Shares the
/// `GlassSliderRail` visual (track + accent lit-fill + white knob) and the
/// leading-origin lit-fill geometry with the timeline zoom slider; unlike
/// `CenterSlider` it is not detented and maps a finger position straight onto the
/// value domain. Press feedback and motion all read from `DesignTokens`.
struct RangeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accessibilityLabel: String = "Range slider"
    var accessibilityValue: String = ""
    var accessibilityIdentifier: String = "DesignPreview-RangeSlider"
    var trackWidth: CGFloat = 450
    /// 拖动状态上抛给宿主行(见 CenterSlider.onDraggingChanged)。
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    // EXPLORATORY: track-bar dimensions are not yet promoted to DesignTokens.
    // Knob (26) and track height (30) mirror CenterSlider so the two read as the
    // same control; promoting these to shared tokens needs a separate human
    // decision (same note as CenterSlider / the zoom slider).
    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26

    private var span: Double {
        let width = range.upperBound - range.lowerBound
        return width > 0 ? width : 1
    }

    private var normalized: CGFloat {
        CGFloat((value - range.lowerBound) / span)
    }

    var body: some View {
        let travel = trackWidth - knobSize
        let knobOffsetX = -travel / 2 + normalized * travel
        let radius = trackHeight / 2
        let leftEdge = -trackWidth / 2
        // Leading-origin lit fill, right cap centred under the knob — same seam
        // trick the zoom slider and CenterSlider use.
        let rightEdge = knobOffsetX + radius
        let litWidth = rightEdge - leftEdge
        let litCenterX = (leftEdge + rightEdge) / 2

        return GlassSliderRail(
            trackWidth: trackWidth,
            trackHeight: trackHeight,
            knobSize: knobSize,
            knobOffsetX: knobOffsetX,
            litCenterX: litCenterX,
            litWidth: litWidth,
            litVisible: normalized > 0.001,
            isDragging: isDragging
        )
        .frame(width: trackWidth, height: trackHeight)
        .gesture(dragGesture)
        .accessibilityElement()
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            // One step = 1% of the range, matching the zoom slider's feel.
            let step = span / 100
            switch direction {
            case .increment: value = clamp(value + step)
            case .decrement: value = clamp(value - step)
            @unknown default: break
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDragging = true
                    }
                    onDraggingChanged(true)
                }
                let travel = max(trackWidth - knobSize, 1)
                let localX = gesture.location.x - knobSize / 2
                let proposed = min(max(localX / travel, 0), 1)
                value = range.lowerBound + Double(proposed) * span
            }
            .onEnded { _ in
                withAnimation(DesignTokens.PressFeedback.control.releaseAnimation) {
                    isDragging = false
                }
                onDraggingChanged(false)
            }
    }

    private func clamp(_ newValue: Double) -> Double {
        min(max(newValue, range.lowerBound), range.upperBound)
    }
}

struct PathBreadcrumbMenu: View {
    let path: [String]
    var onSelectLevel: (Int) -> Void = { _ in }

    private var currentFolder: String {
        path.last ?? ""
    }

    var body: some View {
        Menu {
            // Picker checkmarks the current level (last) on the trailing edge,
            // natively. Selecting any other level routes through `onSelectLevel`.
            Picker(
                "Path",
                selection: Binding(
                    get: { path.count - 1 },
                    set: { onSelectLevel($0) }
                )
            ) {
                ForEach(Array(path.enumerated()), id: \.offset) { index, _ in
                    Text(pathPrefix(through: index)).tag(index)
                }
            }
            .pickerStyle(.inline)
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
        .accessibilityLabel(currentFolder)
    }

    private func pathPrefix(through index: Int) -> String {
        path.prefix(index + 1).joined(separator: " / ")
    }
}

struct SearchInputCapsule: View {
    @Binding var text: String
    var placeholder = "Search"
    var accessibilityIdentifier = "DesignPreview-input-search"

    // 锁死:宽度恒 Card.gridMin,尺寸归容器管,不暴露。
    private let width: CGFloat = DesignTokens.Card.gridMin

    @State private var pressFeedbackTrigger = 0
    @State private var isInputActive = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.tertiary)

            TextField(
                placeholder,
                text: $text,
                onEditingChanged: handleEditingChanged,
                onCommit: deactivateInput
            )
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .focused($isFocused)
                .enchronLiteralTextInput()
                .enchronHoverEffectDisabled()
                .onTapGesture(perform: activateInput)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: width, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .contentShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    DesignTokens.Surface.focusBorder.opacity(isInputActive ? 1 : 0),
                    lineWidth: DesignTokens.Stroke.bold
                )
                .animation(DesignTokens.AnimationToken.selection, value: isInputActive)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                activateInput()
            }
        )
        .sensoryFeedback(.press(.button), trigger: pressFeedbackTrigger)
        .onChange(of: isFocused) { _, focused in
            if !focused {
                setInputActive(false)
            }
        }
        .onSubmit(deactivateInput)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(placeholder)
    }

    private func activateInput() {
        if !isInputActive {
            pressFeedbackTrigger += 1
        }
        setInputActive(true)
        isFocused = true
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        if isEditing {
            setInputActive(true)
        } else {
            deactivateInput()
        }
    }

    private func deactivateInput() {
        setInputActive(false)
        isFocused = false
    }

    private func setInputActive(_ active: Bool) {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isInputActive = active
        }
    }
}

struct SourceSidebarRow: View {
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isActiveSource = false
    var showsSelectionBackground = true

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(isSelected ? DesignTokens.Theme.accent : .secondary)
                .frame(width: DesignTokens.Interactive.mini)

            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if isActiveSource {
                Circle()
                    .fill(DesignTokens.Theme.accent)
                    .frame(width: DesignTokens.Spacing.xs, height: DesignTokens.Spacing.xs)
            }
        }
        .padding(.horizontal, DesignTokens.SourceSidebar.rowPaddingH)
        .frame(minHeight: DesignTokens.SourceSidebar.rowHeight)
        .background(
            isSelected && showsSelectionBackground ? DesignTokens.Surface.selected : .clear,
            in: DesignTokens.SourceSidebar.rowShape
        )
        .opacity(isEnabled ? 1 : 0.42)
        .accessibilityLabel(title)
    }
}

// MARK: - Category sidebar

/// 分类器条目:图标 + 标题 + 稳定 id。
struct CategorySidebarItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
}

/// 通用静态大类分类器侧栏:在 Settings 页面 / Panel 面板中选一个大类。
/// 天生无重排、无删除、无 footer——就是个可选中的静态列表。行视觉复用纯视觉行 `SourceSidebarRow`。
/// 本件是唯一暴露尺寸(`width`/`height` 成对)的标准件,因 Settings 满宽 vs Panel 紧凑,容器管不了。
struct CategorySidebar: View {
    let items: [CategorySidebarItem]
    @Binding var selection: String
    var title: String = "Categories"
    var width: CGFloat = DesignTokens.SourceSidebar.width
    var height: CGFloat? = nil
    var containerIdentifier: String = "CategorySidebar"
    var identifierPrefix: String = "CategorySidebar"

    var body: some View {
        let shape = DesignTokens.SourceSidebar.shape

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(title)
                        .font(DesignTokens.SourceSidebar.sectionTitleFont)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer(minLength: 0)
                    Color.clear
                        .frame(width: DesignTokens.Interactive.compact,
                               height: DesignTokens.Interactive.compact)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, DesignTokens.SourceSidebar.contentPaddingH)

                VStack(spacing: DesignTokens.SourceSidebar.rowSpacing) {
                    ForEach(items) { item in
                        SourceSidebarRow(
                            icon: item.icon,
                            title: item.title,
                            isSelected: selection == item.id
                        )
                        .contentShape(DesignTokens.SourceSidebar.rowShape)
                        .onTapGesture { selection = item.id }
                        .accessibilityAddTraits(selection == item.id ? [.isButton, .isSelected] : .isButton)
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
        .glassBackgroundEffect(.plate, in: shape, displayMode: .always)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerIdentifier)
    }
}

/// 播放 deck 的一个菜单条目(字幕 / 音轨 / 倍速 / 剧集任一项)。
/// 选中态与动作由组合阶段(产品层)提供,deck 只负责呈现与打勾。
struct DeckMenuItem: Identifiable {
    let id: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(id: String, title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }
}

// internal(原 private):融合面板试验场需跨文件复用这个时间轴积木。
struct PrecisionTimelineView: View {
    @Binding var currentTime: Double
    @Binding var pixelsPerSecond: CGFloat

    let duration: Double
    let framesPerSecond: Double
    var onSeekBegan: () -> Void = {}
    var onSeekEnded: (Double) -> Void = { _ in }

    @GestureState private var gestureStartPixelsPerSecond: CGFloat?
    @State private var isDraggingTimeline = false
    @State private var dragStartTime: Double = 0
    @State private var isDraggingZoom = false

    // EXPLORATORY: zoom slider track dimensions not yet promoted to DesignTokens;
    // they mirror CenterSlider's track/knob so the two read as the same control.
    private let zoomTrackWidth: CGFloat = 360
    private let zoomTrackHeight: CGFloat = 30
    private let zoomKnobSize: CGFloat = 26

    // Four-row card: zoom slider, timecode, then ruler + film strip. The card
    // surface is shared with `SettingListGroup` (no extra glass layer). The
    // transport row above lives on the deck, not here.
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            zoomSlider
            timecodeLabel
            rulerAndFilmStrip
        }
        .padding(.horizontal, DesignTokens.PrecisionTimeline.panelPadding)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .enchronListGroupSurface()
        .contentShape(DesignTokens.ShapeToken.card)
        .gesture(zoomGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline")
        .accessibilityLabel("Precision timeline")
    }

    private var timecodeLabel: some View {
        Text(PrecisionTimelineFormatter.timecode(currentTime, framesPerSecond: framesPerSecond))
            .font(DesignTokens.Typography.headline)
            .monospacedDigit()
            .foregroundStyle(DesignTokens.PrecisionTimeline.timecodeColor)
            .accessibilityIdentifier("DesignPreview-PrecisionTimeline-timecode")
    }

    private var zoomSlider: some View {
        let travel = zoomTrackWidth - zoomKnobSize
        let normalized = normalizedZoom
        let knobOffsetX = -travel / 2 + normalized * travel
        let radius = zoomTrackHeight / 2
        let leftEdge = -zoomTrackWidth / 2
        // Leading-origin lit fill. The right cap is centred on the knob (extend
        // the fill by the track radius) so the rounded cap sits *under* the knob
        // with no seam — the same trick `CenterSlider` uses.
        let rightEdge = knobOffsetX + radius
        let litWidth = rightEdge - leftEdge
        let litCenterX = (leftEdge + rightEdge) / 2

        return HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            GlassSliderRail(
                trackWidth: zoomTrackWidth,
                trackHeight: zoomTrackHeight,
                knobSize: zoomKnobSize,
                knobOffsetX: knobOffsetX,
                litCenterX: litCenterX,
                litWidth: litWidth,
                litVisible: normalized > 0.001,
                isDragging: isDraggingZoom
            )
            .frame(width: zoomTrackWidth, height: zoomTrackHeight)
            .gesture(zoomSliderGesture)

            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .font(.body)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-zoom")
        .accessibilityLabel("Timeline zoom")
        .accessibilityValue("\(Int(normalized * 100))%")
    }

    private var zoomSliderGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDraggingZoom {
                    withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
                        isDraggingZoom = true
                    }
                }
                let travel = max(zoomTrackWidth - zoomKnobSize, 1)
                let localX = value.location.x - zoomKnobSize / 2
                let normalized = min(max(localX / travel, 0), 1)
                pixelsPerSecond = zoomValue(forNormalized: normalized)
            }
            .onEnded { _ in
                withAnimation(DesignTokens.PressFeedback.control.releaseAnimation) {
                    isDraggingZoom = false
                }
            }
    }

    private var rulerAndFilmStrip: some View {
        GeometryReader { proxy in
            let viewportWidth = max(proxy.size.width, 1)
            let safePixelsPerSecond = clampedPixelsPerSecond(pixelsPerSecond)
            let leadingX = viewportWidth / 2 - CGFloat(currentTime) * safePixelsPerSecond
            let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.element, style: .continuous)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DesignTokens.PrecisionTimeline.emptyAreaFill)

                timelineRuler(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: safePixelsPerSecond
                )
                .frame(height: DesignTokens.PrecisionTimeline.rulerHeight)

                filmStrip(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: safePixelsPerSecond,
                    height: max(proxy.size.height - DesignTokens.PrecisionTimeline.rulerHeight, 1)
                )
                .offset(y: DesignTokens.PrecisionTimeline.rulerHeight)

                playhead(
                    x: viewportWidth / 2,
                    height: proxy.size.height
                )
            }
            .clipShape(shape)
            .enchronHoverContentShape(shape)
            .enchronHoverEffect(.automatic)
            .contentShape(shape)
            .gesture(timelineDragGesture(pixelsPerSecond: safePixelsPerSecond))
        }
    }

    private func timelineRuler(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> some View {
        Canvas { context, size in
            let intervals = tickIntervals(pixelsPerSecond: pixelsPerSecond)
            drawTicks(
                context: &context,
                size: size,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond,
                interval: intervals.minor,
                height: DesignTokens.PrecisionTimeline.minorTickHeight,
                color: DesignTokens.PrecisionTimeline.minorTickColor,
                lineWidth: DesignTokens.Stroke.subtle
            )
            drawTicks(
                context: &context,
                size: size,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond,
                interval: intervals.major,
                height: DesignTokens.PrecisionTimeline.majorTickHeight,
                color: DesignTokens.PrecisionTimeline.majorTickColor,
                lineWidth: DesignTokens.Stroke.regular
            )
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(visibleTickTimes(
                    viewportWidth: viewportWidth,
                    leadingX: leadingX,
                    pixelsPerSecond: pixelsPerSecond,
                    interval: tickIntervals(pixelsPerSecond: pixelsPerSecond).major
                ), id: \.self) { time in
                    Text(PrecisionTimelineFormatter.clock(time))
                        .font(DesignTokens.Typography.monospacedDetail)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.PrecisionTimeline.secondaryTextColor)
                        .position(
                            x: leadingX + CGFloat(time) * pixelsPerSecond,
                            y: DesignTokens.Spacing.sm
                        )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func filmStrip(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        height: CGFloat
    ) -> some View {
        Canvas { context, size in
            drawFilmStrip(
                context: &context,
                size: size,
                viewportWidth: viewportWidth,
                leadingX: leadingX,
                pixelsPerSecond: pixelsPerSecond
            )
        }
        .frame(height: height)
    }

    private func playhead(x: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(DesignTokens.PrecisionTimeline.playheadColor)
            .frame(width: DesignTokens.PrecisionTimeline.playheadWidth)
            .overlay(alignment: .top) {
                Circle()
                    .fill(DesignTokens.PrecisionTimeline.playheadAccent)
                    .frame(
                        width: DesignTokens.Spacing.sm,
                        height: DesignTokens.Spacing.sm
                    )
                    .offset(y: -DesignTokens.Spacing.xs)
            }
            .frame(height: height)
            .position(
                x: x,
                y: height / 2
            )
            .allowsHitTesting(false)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureStartPixelsPerSecond) { _, state, _ in
                if state == nil {
                    state = pixelsPerSecond
                }
            }
            .onChanged { value in
                let start = gestureStartPixelsPerSecond ?? pixelsPerSecond
                pixelsPerSecond = clampedPixelsPerSecond(start * value.magnification)
            }
    }

    private func timelineDragGesture(pixelsPerSecond: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                if !isDraggingTimeline {
                    isDraggingTimeline = true
                    dragStartTime = currentTime
                    onSeekBegan()
                }

                let delta = Double(value.translation.width / pixelsPerSecond)
                let targetTime = dragStartTime - delta
                currentTime = quantizedIfNeeded(clampedTime(targetTime))
            }
            .onEnded { _ in
                isDraggingTimeline = false
                onSeekEnded(currentTime)
            }
    }

    private func drawTicks(
        context: inout GraphicsContext,
        size: CGSize,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        interval: Double,
        height: CGFloat,
        color: Color,
        lineWidth: CGFloat
    ) {
        guard interval > 0, duration > 0 else { return }

        let visibleTimes = visibleTickTimes(
            viewportWidth: size.width,
            leadingX: leadingX,
            pixelsPerSecond: pixelsPerSecond,
            interval: interval
        )
        let centerY = size.height - DesignTokens.Spacing.xs

        for time in visibleTimes {
            let x = leadingX + CGFloat(time) * pixelsPerSecond
            var path = Path()
            path.move(to: CGPoint(x: x, y: centerY - height))
            path.addLine(to: CGPoint(x: x, y: centerY))
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
    }

    private func drawFilmStrip(
        context: inout GraphicsContext,
        size: CGSize,
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat
    ) {
        guard duration > 0 else { return }

        let contentWidth = CGFloat(duration) * pixelsPerSecond
        let segmentWidth = max(
            DesignTokens.PrecisionTimeline.thumbnailMinWidth,
            pixelsPerSecond * DesignTokens.PrecisionTimeline.thumbnailSecondsScale
        )
        let visibleStart = max(-leadingX, 0)
        // 唯一事实是 contentWidth(= duration×pps),拖拽极限/标尺/胶片末端都以它为准,
        // 不再单独截短整体(那会与拖拽极限脱节,且最小缩放时一格≈数十秒,白白丢失可拖范围)。
        let visibleEnd = min(viewportWidth - leadingX, contentWidth)
        guard visibleStart < visibleEnd else { return }

        let visibleFilmRect = CGRect(
            x: leadingX + visibleStart,
            y: 0,
            width: visibleEnd - visibleStart,
            height: size.height
        )
        context.fill(
            Path(visibleFilmRect),
            with: .color(DesignTokens.PrecisionTimeline.filmStripBase)
        )

        // segmentWidth 不整除 contentWidth 时,末尾会余下一截。把它并入最后一个完整格
        // (lastDrawIndex 的右边界钉到 contentWidth),让胶片干净收在内容边界上——既不
        // 切到方块中间,也不留半格细条;余量较大(≥半格)时则自成一格。
        let fullCount = Int(floor(contentWidth / segmentWidth))
        let remainder = contentWidth - CGFloat(fullCount) * segmentWidth
        let lastDrawIndex = (remainder >= segmentWidth * 0.5) ? fullCount : max(fullCount - 1, 0)

        let startIndex = max(Int(floor(visibleStart / segmentWidth)), 0)
        let endIndex = min(max(Int(ceil(visibleEnd / segmentWidth)), startIndex), lastDrawIndex)
        guard startIndex <= endIndex else { return }

        var stripContext = context
        stripContext.clip(to: Path(visibleFilmRect))

        for index in startIndex...endIndex {
            let leftContentX = CGFloat(index) * segmentWidth
            // 最后一格的右边界永远钉在 contentWidth,与底板/拖拽极限对齐。
            let rightContentX = (index == lastDrawIndex)
                ? contentWidth
                : CGFloat(index + 1) * segmentWidth
            let rect = CGRect(
                x: leadingX + leftContentX,
                y: DesignTokens.PrecisionTimeline.filmImageInset,
                width: max(rightContentX - leftContentX, 1),
                height: max(size.height - DesignTokens.PrecisionTimeline.filmImageInset * 2, 1)
            )
            let palette = DesignTokens.PrecisionTimeline.thumbnailPalette
            let color = palette[index % palette.count]
            let path = Path(rect.insetBy(dx: DesignTokens.Stroke.regular, dy: DesignTokens.Stroke.subtle))

            stripContext.fill(path, with: .color(color))
            stripContext.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.minY + DesignTokens.Stroke.regular,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.34
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripHighlight)
            )
            stripContext.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.midY,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.5
                )),
                with: .color(Color.black.opacity(0.12))
            )
            stripContext.fill(
                Path(CGRect(
                    x: rect.maxX - DesignTokens.PrecisionTimeline.thumbnailSeparatorWidth,
                    y: rect.minY,
                    width: DesignTokens.PrecisionTimeline.thumbnailSeparatorWidth,
                    height: rect.height
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripSeparator)
            )
        }

        drawSprockets(
            context: &context,
            size: size,
            leadingX: leadingX,
            visibleStart: visibleStart,
            visibleEnd: visibleEnd
        )
    }

    private func drawSprockets(
        context: inout GraphicsContext,
        size: CGSize,
        leadingX: CGFloat,
        visibleStart: CGFloat,
        visibleEnd: CGFloat
    ) {
        let holeWidth = DesignTokens.PrecisionTimeline.sprocketWidth
        let holeHeight = DesignTokens.PrecisionTimeline.sprocketHeight
        let step = holeWidth + DesignTokens.PrecisionTimeline.sprocketSpacing
        guard step > 0 else { return }

        // 只画完整落在 [visibleStart, visibleEnd] 内的齿孔,避免右边界外冒出半截/孤立的孔。
        let startIndex = max(Int(ceil(visibleStart / step)), 0)
        let endIndex = Int(floor((visibleEnd - holeWidth) / step))
        guard startIndex <= endIndex else { return }
        let topY = DesignTokens.Spacing.xxs
        let bottomY = size.height - holeHeight - DesignTokens.Spacing.xxs

        for index in startIndex...endIndex {
            let x = leadingX + CGFloat(index) * step
            let topRect = CGRect(x: x, y: topY, width: holeWidth, height: holeHeight)
            let bottomRect = CGRect(x: x, y: bottomY, width: holeWidth, height: holeHeight)
            let topPath = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .path(in: topRect)
            let bottomPath = RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .path(in: bottomRect)

            context.fill(topPath, with: .color(DesignTokens.PrecisionTimeline.sprocketFill))
            context.fill(bottomPath, with: .color(DesignTokens.PrecisionTimeline.sprocketFill))
        }
    }

    private func visibleTickTimes(
        viewportWidth: CGFloat,
        leadingX: CGFloat,
        pixelsPerSecond: CGFloat,
        interval: Double
    ) -> [Double] {
        guard interval > 0, pixelsPerSecond > 0 else { return [] }

        let startTime = max(0, Double((-leadingX - DesignTokens.Spacing.lg) / pixelsPerSecond))
        let endTime = min(
            duration,
            Double((viewportWidth - leadingX + DesignTokens.Spacing.lg) / pixelsPerSecond)
        )
        guard startTime <= endTime else { return [] }

        let firstTick = floor(startTime / interval) * interval
        let tickCount = Int(ceil((endTime - firstTick) / interval))

        return (0...max(tickCount, 0))
            .map { firstTick + Double($0) * interval }
            .filter { $0 >= 0 && $0 <= duration }
    }

    private func tickIntervals(pixelsPerSecond: CGFloat) -> (minor: Double, major: Double) {
        let secondsPerPoint = 1 / Double(max(pixelsPerSecond, 0.001))
        let frameInterval = 1 / max(framesPerSecond, 1)
        let intervals = niceIntervals(frameInterval: frameInterval)
        let minorTarget = secondsPerPoint * Double(DesignTokens.PrecisionTimeline.minorTickTargetSpacing)
        let majorTarget = secondsPerPoint * Double(DesignTokens.PrecisionTimeline.majorTickTargetSpacing)
        let minor = intervals.first { $0 >= minorTarget } ?? max(minorTarget, frameInterval)
        let major = intervals.first { $0 >= max(majorTarget, minor * 2) } ?? max(majorTarget, minor * 2)

        return (minor, major)
    }

    private func niceIntervals(frameInterval: Double) -> [Double] {
        [
            frameInterval,
            frameInterval * 2,
            frameInterval * 4,
            0.25,
            0.5,
            1,
            2,
            5,
            10,
            15,
            30,
            60,
            120,
            300,
            600,
            1_200,
            1_800,
            3_600
        ]
    }

    private var zoomLabel: String {
        let secondsInView = Double(availableTimelineWidth / max(clampedPixelsPerSecond(pixelsPerSecond), 0.001))
        return "\(PrecisionTimelineFormatter.clock(secondsInView)) visible"
    }

    private var availableTimelineWidth: CGFloat {
        DesignTokens.PrecisionTimeline.expandedWidth - DesignTokens.PrecisionTimeline.panelPadding * 2
    }

    private var normalizedZoom: CGFloat {
        let minValue = log(Double(DesignTokens.PrecisionTimeline.minPixelsPerSecond))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let current = log(Double(clampedPixelsPerSecond(pixelsPerSecond)))
        guard maxValue > minValue else { return 0 }
        return CGFloat(min(max((current - minValue) / (maxValue - minValue), 0), 1))
    }

    private func zoomValue(forNormalized normalized: CGFloat) -> CGFloat {
        let minValue = log(Double(DesignTokens.PrecisionTimeline.minPixelsPerSecond))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let value = minValue + (maxValue - minValue) * Double(normalized)
        return clampedPixelsPerSecond(CGFloat(exp(value)))
    }

    private var frameDuration: Double {
        1 / max(framesPerSecond, 1)
    }

    private func quantizedIfNeeded(_ time: Double) -> Double {
        let pointsPerFrame = clampedPixelsPerSecond(pixelsPerSecond) * CGFloat(frameDuration)
        guard pointsPerFrame >= DesignTokens.Spacing.xs else { return time }
        return (time / frameDuration).rounded() * frameDuration
    }

    private func clampedTime(_ time: Double) -> Double {
        min(max(time, 0), duration)
    }

    private func clampedPixelsPerSecond(_ value: CGFloat) -> CGFloat {
        min(
            max(value, DesignTokens.PrecisionTimeline.minPixelsPerSecond),
            DesignTokens.PrecisionTimeline.maxPixelsPerSecond
        )
    }
}

private enum PrecisionTimelineFormatter {
    static func clock(_ seconds: Double) -> String {
        let clamped = max(seconds, 0)
        let totalSeconds = Int(clamped.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func timecode(_ seconds: Double, framesPerSecond: Double) -> String {
        let frameRate = max(Int(framesPerSecond.rounded()), 1)
        let totalFrames = max(Int((seconds * Double(frameRate)).rounded()), 0)
        let framesPerHour = frameRate * 3_600
        let framesPerMinute = frameRate * 60
        let hours = totalFrames / framesPerHour
        let minutes = (totalFrames % framesPerHour) / framesPerMinute
        let secs = (totalFrames % framesPerMinute) / frameRate
        let frame = totalFrames % frameRate

        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, secs, frame)
    }
}

// MARK: - Loading spinner

/// Arc shape with independently animatable start/end values.
private struct SpinnerArc: Shape {
    var start: CGFloat
    var end: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) * 0.38,
            startAngle: .degrees(start * 360 - 120),
            endAngle: .degrees(end * 360 - 120),
            clockwise: false
        )
        return path
    }
}

struct LoadingSpinner: View {
    var size: CGFloat = 56
    var showBorder: Bool = true

    @State private var arcStart: CGFloat = 0
    @State private var arcEnd: CGFloat = 0

    var body: some View {
        let lineWidth = size * 0.06
        let inset = size * 0.16

        ZStack {
            // Glow layer — theme-colored, screen blend, follows arc
            SpinnerArc(start: arcStart, end: arcEnd)
                .stroke(
                    DesignTokens.Theme.accent.opacity(0.15),
                    style: StrokeStyle(lineWidth: lineWidth * 4, lineCap: .round)
                )
                .blur(radius: lineWidth * 2)
                .blendMode(.screen)
                .padding(inset)

            // White arc
            SpinnerArc(start: arcStart, end: arcEnd)
                .stroke(
                    .white.opacity(0.9),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .padding(inset)
        }
        .frame(width: size, height: size)
        .overlay {
            if showBorder {
                Circle()
                    .strokeBorder(DesignTokens.Theme.accent.opacity(0.3), lineWidth: 1)
            }
        }
        .clipShape(Circle())
        .glassBackgroundEffect(in: Circle())
        .onAppear { runLoop() }
    }

    private func runLoop() {
        Task {
            while !Task.isCancelled {
                // Head extends forward from gap
                withAnimation(DesignTokens.LoadingSpinner.headAnimation) {
                    arcEnd = 0.85
                }
                try? await Task.sleep(for: DesignTokens.LoadingSpinner.headDuration)

                // Tail catches up to head
                withAnimation(DesignTokens.LoadingSpinner.tailAnimation) {
                    arcStart = 0.85
                }
                try? await Task.sleep(for: DesignTokens.LoadingSpinner.tailDuration)

                // Instant reset to start position
                arcStart = 0
                arcEnd = 0
            }
        }
    }
}

// MARK: - Fused player panel (迁自 DesignPreview/ContentView,ADR-0009 收口)

/// 注入式播放/模式绑定:nil = Canvas mock(默认,DesignPreview 走此路),主 App 注真。
/// 合并 transport 面(原 PlayerControlDeckLive)+ 两个模式入口(全景 / 虚拟场景)。
/// ADR-0009:取代 PlayerControlDeckLive。
struct FusedPlayerPanelLive {
    var presentation: PlaybackPresentation
    var canDock: Bool
    var canEnterPanorama: Bool
    var screenScale: Double
    var recommendedScreenScale: Double
    var isPlaying: Bool
    var showsReplay: Bool
    var progress: CGFloat
    var elapsedLabel: String
    var remainingLabel: String
    var duration: Double
    var framesPerSecond: Double
    var onPlayPause: () -> Void
    var onSkipBackward: () -> Void
    var onSkipForward: () -> Void
    var onSeek: (CGFloat) -> Void
    var onFrameStep: (Int) -> Void
    /// ⤢ 展开按钮:进入全景穹顶(.panorama)。
    var onEnterPanorama: () -> Void
    /// Dock 按钮进入当前或默认 Environment 的 Docked presentation。
    var onEnterImmersive: () -> Void
    var onExitSpatial: () -> Void
    var onSetScreenScale: (Double) -> Void
    var onResetScreenScale: () -> Void
    var subtitleItems: [DeckMenuItem]
    var audioItems: [DeckMenuItem]
    var speedItems: [DeckMenuItem]
    var episodeItems: [DeckMenuItem]
}

struct FusedPlayerPanel: View {
    /// 实时播放绑定。nil = Canvas mock(默认);注入后接真实播放状态与交互。
    var live: FusedPlayerPanelLive?
    /// 面板级交互回调(≡ 开合设置、双击开合时间轴)。主 App 用它重置自动隐藏计时器,
    /// 对齐原 deck 的 onOpenSettings→register() 行为。默认 no-op(Canvas 无计时器)。
    var onInteraction: () -> Void = {}

    // initialTimelineExpanded 仅供 Canvas 审查直接展示展开态。
    init(
        live: FusedPlayerPanelLive? = nil,
        onInteraction: @escaping () -> Void = {},
        initialTimelineExpanded: Bool = false
    ) {
        self.live = live
        self.onInteraction = onInteraction
        _timelineExpanded = State(initialValue: initialTimelineExpanded)
    }

    @State private var timelineExpanded = false

    // 进度条状态。拖动中用本地 progress(跟手);非拖动镜像 live 位置;live 为 nil 退化纯本地 mock。
    @State private var progress: CGFloat = 0.45
    @State private var isDragging = false
    @State private var isTimelineDragging = false
    @State private var isProgressHovered = false
    @State private var isIgnoringDrag = false
    @State private var dragStartProgress: CGFloat = 0.45
    /// Seek 完成锁存:松手 onSeek 后,live.progress 异步才追上,锁存期内拇指钉在目标值,
    /// 避免"跳回旧位再闪到目标"。live 追上(或超时兜底)即释放。
    @State private var pendingSeekTarget: CGFloat?
    @State private var scrubFeedbackTrigger = 0
    @State private var minimumBoundaryFeedbackTrigger = 0
    @State private var maximumBoundaryFeedbackTrigger = 0
    @State private var timelineFeedbackTrigger = 0
    @State private var announcedBoundary: ProgressBoundary?
    @State private var pixelsPerSecond: CGFloat = DesignTokens.PrecisionTimeline.initialPixelsPerSecond
    // ⋯ 菜单 Canvas mock 选择态(live 为 nil 时)。
    @State private var selectedSubtitle = "Off"
    @State private var selectedAudioTrack = "English 5.1"
    @State private var selectedSpeed = "1×"
    @Namespace private var hoverNamespace

    private enum ProgressBoundary { case minimum, maximum }

    // 拖动中用本地 progress(视觉跟手);松手回调 onSeek。非拖动时镜像 live 位置;
    // 锁存期内钉在 pendingSeekTarget;live 为 nil 退化纯本地 @State(Canvas mock)。
    private var displayProgress: CGFloat {
        if isDragging || isTimelineDragging { return progress }
        if let pendingSeekTarget { return pendingSeekTarget }
        return live?.progress ?? progress
    }

    private let expandedWidth: CGFloat = 880

    private var isExpanded: Bool { timelineExpanded }
    private var clusterWidth: CGFloat {
        isExpanded ? expandedWidth : DesignTokens.ProgressBar.previewWidth
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            controlsRow

            if let live, live.presentation == .docked {
                screenSizeControl(live)
            }

            // 控件簇第二行(与按钮同属"播放控制",无分界线):时间轴收起时是进度条
            // ——进度条本身就是打开时间轴的按钮(双击展开);展开时同槽位换成时间轴本体。
            if timelineExpanded {
                timelineBlock
            } else {
                progressBar
            }

        }
        .padding(DesignTokens.Spacing.xl)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        // 旋转(向用户抬起 30°)留到真实窗口/ornament 语境再加——Canvas 预览不出空间旋转。
        .animation(DesignTokens.AnimationToken.panelSpring, value: timelineExpanded)
        .sensoryFeedback(.press(.slider), trigger: scrubFeedbackTrigger)
        .sensoryFeedback(.selection(.minimum), trigger: minimumBoundaryFeedbackTrigger)
        .sensoryFeedback(.selection(.maximum), trigger: maximumBoundaryFeedbackTrigger)
        .sensoryFeedback(.selection(.on), trigger: timelineFeedbackTrigger)
        .onChange(of: live?.progress) { _, newValue in
            // 锁存释放:player 报告的位置追上(容差内)目标即放行。
            guard let target = pendingSeekTarget, let newValue else { return }
            if abs(newValue - target) < 0.02 { pendingSeekTarget = nil }
        }
        .task(id: pendingSeekTarget) {
            // 兜底:player 永远不精确落到目标时,别让锁存无限钉住拇指。
            guard pendingSeekTarget != nil else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            pendingSeekTarget = nil
        }
    }

    private func screenSizeControl(_ live: FusedPlayerPanelLive) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("Screen Size")
                .font(DesignTokens.Typography.metadata)

            Slider(
                value: Binding(
                    get: { live.screenScale },
                    set: { live.onSetScreenScale($0) }
                ),
                in: PlaybackScreenSize.scaleRange,
                step: PlaybackScreenSize.scaleStep,
                onEditingChanged: { _ in onInteraction() }
            )
            .accessibilityIdentifier("PlayerPanel-ScreenSize-slider")
            .accessibilityLabel("Screen Size")
            .accessibilityValue("\(Int((live.screenScale * 100).rounded())) percent")

            Text("\(Int((live.screenScale * 100).rounded()))%")
                .font(DesignTokens.Typography.metadata.monospacedDigit())
                .frame(minWidth: 52, alignment: .trailing)
                .accessibilityIdentifier("PlayerPanel-ScreenSize-value")

            Button("Reset") {
                onInteraction()
                live.onResetScreenScale()
            }
            .buttonStyle(.borderless)
            .disabled(abs(live.screenScale - live.recommendedScreenScale) < 0.001)
            .accessibilityIdentifier("PlayerPanel-ScreenSize-reset")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PlayerPanel-ScreenSize")
    }

    @ViewBuilder
    private var controlsRow: some View {
        if (live?.presentation ?? .window) == .window {
            HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                GlassCircleIconButton(
                    systemName: "slider.horizontal.3",
                    accessibilityLabel: timelineExpanded ? "Collapse playback panel" : "Expand playback panel",
                    action: { timelineExpanded ? closeTimeline() : openTimeline() },
                    accessibilityIdentifier: "PlayerPanel-button-expand"
                )
                GlassCircleIconButton(
                    systemName: "square.stack.3d.up",
                    accessibilityLabel: "Docking",
                    action: { live?.onEnterImmersive() },
                    accessibilityIdentifier: "PlayerPanel-button-dock"
                )
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!(live?.canDock ?? true))
                rewindButton
                playButton
                forwardButton
                #if os(visionOS)
                GlassCircleIconButton(
                    systemName: "pano",
                    accessibilityLabel: "Panorama",
                    action: { live?.onEnterPanorama() },
                    accessibilityIdentifier: "PlayerPanel-button-panorama"
                )
                .disabled(!(live?.canEnterPanorama ?? true))
                #endif
                moreMenu
            }
            .frame(width: clusterWidth)
        } else if let live {
            HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
                GlassCircleIconButton(
                    systemName: live.presentation == .docked ? "rectangle.portrait.and.arrow.forward" : "pano",
                    accessibilityLabel: live.presentation == .docked ? "Undock" : "Exit Panorama",
                    action: live.onExitSpatial,
                    accessibilityIdentifier: "PlayerPanel-button-exit-spatial"
                )
                .keyboardShortcut(.escape, modifiers: [])
                rewindButton
                playButton
                forwardButton
                moreMenu
            }
            .frame(width: clusterWidth)
        }
    }

    private var rewindButton: some View {
        GlassCircleIconButton(
            systemName: timelineExpanded ? "backward.frame" : "gobackward.10",
            accessibilityLabel: timelineExpanded ? "Previous frame" : "Rewind 10 seconds",
            action: { timelineExpanded ? stepFrame(-1) : live?.onSkipBackward() },
            accessibilityIdentifier: "PlayerPanel-button-rewind"
        )
        .keyboardShortcut(.leftArrow, modifiers: [])
    }

    private var forwardButton: some View {
        GlassCircleIconButton(
            systemName: timelineExpanded ? "forward.frame" : "goforward.10",
            accessibilityLabel: timelineExpanded ? "Next frame" : "Forward 10 seconds",
            action: { timelineExpanded ? stepFrame(1) : live?.onSkipForward() },
            accessibilityIdentifier: "PlayerPanel-button-forward"
        )
        .keyboardShortcut(.rightArrow, modifiers: [])
    }

    // ⋯ 菜单:玻璃圆(GlassCircleIconLabel)作 Menu label,内容 live 注入时来自产品层、
    // 否则 Canvas mock。命中尺寸对齐其它 transport 玻璃圆(large 60)。
    private var moreMenu: some View {
        Menu {
            if let live {
                liveMoreMenuSections(live)
            } else {
                mockMoreMenuSections
            }
        } label: {
            GlassCircleIconLabel(
                systemName: "ellipsis",
                accessibilityLabel: "More",
                accessibilityIdentifier: "PlayerPanel-menu-more"
            )
        }
        .buttonStyle(.plain)
        .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
        .contentShape(Circle())
        .accessibilityIdentifier("PlayerPanel-menu-more")
        .accessibilityLabel("More playback settings")
    }

    /// 逐帧步进:live 注入时回调产品层;否则在 mock 本地 progress 上挪一帧。
    private func stepFrame(_ direction: Double) {
        if let live {
            live.onFrameStep(direction < 0 ? -1 : 1)
            return
        }
        let fps = DesignTokens.PrecisionTimeline.previewFrameRate
        let duration = DesignTokens.PrecisionTimeline.previewDuration
        guard fps > 0, duration > 0 else { return }
        let frameDuration = 1 / fps
        let currentTime = Double(progress) * duration
        let nextTime = min(max(currentTime + direction * frameDuration, 0), duration)
        progress = CGFloat(nextTime / duration)
    }

    private var playButton: some View {
        GlassCircleIconButton(
            systemName: primaryPlayIcon,
            accessibilityLabel: primaryPlayLabel,
            action: { live?.onPlayPause() },
            accessibilityIdentifier: "PlayerPanel-button-play",
            visualSize: DesignTokens.Interactive.xl,
            targetSize: DesignTokens.Interactive.xl,
            font: DesignTokens.SymbolSize.action
        )
        .keyboardShortcut(.space, modifiers: [])
    }

    private var primaryPlayIcon: String {
        guard let live else { return "play.fill" }
        if live.showsReplay { return "arrow.counterclockwise" }
        return live.isPlaying ? "pause.fill" : "play.fill"
    }

    private var primaryPlayLabel: String {
        guard let live else { return "Play" }
        if live.showsReplay { return "Replay" }
        return live.isPlaying ? "Pause" : "Play"
    }

    // MARK: ⋯ 菜单内容(live 注入 / Canvas mock 两路,抄自原 PlayerControlDeck)

    @ViewBuilder
    private var mockMoreMenuSections: some View {
        Section("Playback Settings") {
            mockSelectableMenu("Subtitles", ["Off", "English CC", "中文简体", "Auto"], selection: $selectedSubtitle)
            mockSelectableMenu("Audio Track", ["English 5.1", "Japanese 2.0", "Commentary"], selection: $selectedAudioTrack)
            mockSelectableMenu(
                "Playback Speed",
                ["0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×", "3×", "5×"],
                selection: $selectedSpeed
            )
            Menu("Episodes") {
                menuOption("Episode 1 · The Signal")
                menuOption("Episode 2 · Night Crossing")
                menuOption("Episode 3 · Glass Harbor")
                menuOption("Episode 4 · Quiet Orbit")
                menuOption("Episode 5 · Afterimage")
                menuOption("Episode 6 · The Long Return")
            }
        }
    }

    @ViewBuilder
    private func liveMoreMenuSections(_ live: FusedPlayerPanelLive) -> some View {
        Section("Playback Settings") {
            if !live.subtitleItems.isEmpty {
                Menu("Subtitles") {
                    liveMenuItems(live.subtitleItems, category: "subtitle")
                }
                .accessibilityIdentifier("PlayerPanel-menu-subtitles")
            }
            if !live.audioItems.isEmpty {
                Menu("Audio Track") {
                    liveMenuItems(live.audioItems, category: "audio")
                }
                .accessibilityIdentifier("PlayerPanel-menu-audio")
            }
            Menu("Playback Speed") {
                liveMenuItems(live.speedItems, category: "speed")
            }
            .accessibilityIdentifier("PlayerPanel-menu-speed")
            if !live.episodeItems.isEmpty {
                Menu("Episodes") {
                    liveMenuItems(live.episodeItems, category: "episode")
                }
                .accessibilityIdentifier("PlayerPanel-menu-episodes")
            }
        }
    }

    @ViewBuilder
    private func liveMenuItems(
        _ items: [DeckMenuItem],
        category: String
    ) -> some View {
        Picker("", selection: liveSelection(items)) {
            ForEach(items) { item in
                Text(item.title)
                    .tag(item.id)
                    .accessibilityIdentifier("PlayerPanel-menu-\(category)-\(item.id)")
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func liveSelection(_ items: [DeckMenuItem]) -> Binding<String> {
        Binding(
            get: { items.first(where: \.isSelected)?.id ?? "" },
            set: { id in items.first(where: { $0.id == id })?.action() }
        )
    }

    private func menuOption(_ title: String) -> some View {
        Button {} label: { Text(title) }
    }

    private func mockSelectableMenu(
        _ title: String,
        _ options: [String],
        selection: Binding<String>
    ) -> some View {
        Menu(title) {
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    // MARK: Timeline(展开态)

    private var timelineBlock: some View {
        PrecisionTimelineView(
            currentTime: timelineCurrentTime,
            pixelsPerSecond: $pixelsPerSecond,
            duration: timelineDuration,
            framesPerSecond: timelineFramesPerSecond,
            onSeekBegan: beginTimelineSeek,
            onSeekEnded: commitTimelineSeek
        )
        .frame(width: expandedWidth, height: DesignTokens.PrecisionTimeline.expandedHeight)
        .transition(.opacity)
        // 对称:双击进度条展开,双击时间轴收起。
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded { closeTimeline() })
    }

    private var timelineCurrentTime: Binding<Double> {
        Binding(
            get: { Double(displayProgress) * timelineDuration },
            set: { newValue in
                progress = timelineDuration > 0 ? CGFloat(newValue / timelineDuration) : 0
            }
        )
    }

    private var timelineDuration: Double {
        guard let duration = live?.duration, duration > 0 else {
            return DesignTokens.PrecisionTimeline.previewDuration
        }
        return duration
    }

    private var timelineFramesPerSecond: Double {
        guard let framesPerSecond = live?.framesPerSecond, framesPerSecond > 0 else {
            return DesignTokens.PrecisionTimeline.previewFrameRate
        }
        return framesPerSecond
    }

    private func commitTimelineSeek(_ seconds: Double) {
        isTimelineDragging = false
        guard let live, timelineDuration > 0 else { return }
        let target = CGFloat(min(max(seconds / timelineDuration, 0), 1))
        progress = target
        pendingSeekTarget = target
        live.onSeek(target)
    }

    private func beginTimelineSeek() {
        progress = displayProgress
        isTimelineDragging = true
        onInteraction()
    }

    // MARK: Progress bar(收起态;双击展开时间轴)—— 整套抄自 PlayerControlDeck

    private var trackScale: CGFloat {
        isDragging ? 1 : DesignTokens.ProgressBar.inactiveScale
    }

    private var hoverActivationGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "fused-progress-reveal", in: hoverNamespace, behavior: .activatesGroup)
    }

    private var hoverRevealGroup: EnchronHoverGroup {
        EnchronHoverGroup(id: "fused-progress-reveal", in: hoverNamespace, behavior: .followsGroup)
    }

    private var progressBar: some View {
        let overlayWidth = clusterWidth
        let width = max(overlayWidth - DesignTokens.ProgressBar.thumbDiameter, 0)
        let clampedProgress = min(max(displayProgress, 0), 1)
        let thumbX = DesignTokens.ProgressBar.thumbDiameter / 2 + clampedProgress * width
        return progressBarBody(
            width: width,
            clampedProgress: clampedProgress,
            thumbX: thumbX,
            overlayWidth: overlayWidth
        )
        .transition(.opacity)
    }

    private func progressBarBody(
        width: CGFloat,
        clampedProgress: CGFloat,
        thumbX: CGFloat,
        overlayWidth: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            hoverCarrier(width: overlayWidth)

            progressHub(
                width: width,
                progress: clampedProgress,
                overlayWidth: overlayWidth,
                scale: trackScale
            )

            timeBubble
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2 - DesignTokens.ProgressBar.timeBubbleOffset
                )
                .enchronHoverOpacity(
                    active: 1,
                    inactive: 0,
                    in: hoverRevealGroup,
                    forcedActive: isDragging || isProgressHovered,
                    animation: DesignTokens.AnimationToken.selection,
                    macUsesLocalHover: true
                )
                .allowsHitTesting(false)

            scrubberControl(width: width)
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2
                )
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .contentShape(.interaction, Capsule())
        .onHover { isProgressHovered = $0 }
        .gesture(dragGesture(width: width, thumbX: thumbX))
        // 双击进度条任意处展开时间轴。
        .simultaneousGesture(TapGesture(count: 2).onEnded { openTimeline() })
    }

    private func hoverCarrier(width: CGFloat) -> some View {
        Capsule()
            .fill(DesignTokens.ProgressBar.hoverCarrierFill)
            .frame(width: width, height: DesignTokens.ProgressBar.hitHeight)
            .enchronHoverContentShape(Capsule())
            .enchronHoverOpacity(
                active: 1,
                inactive: DesignTokens.ProgressBar.hoverCarrierInactiveOpacity,
                in: hoverActivationGroup,
                forcedActive: isProgressHovered,
                animation: DesignTokens.AnimationToken.selection,
                macUsesLocalHover: true
            )
            .contentShape(.interaction, Capsule())
            .accessibilityHidden(true)
    }

    private func progressHub(
        width: CGFloat,
        progress: CGFloat,
        overlayWidth: CGFloat,
        scale: CGFloat
    ) -> some View {
        ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(width: overlayWidth, height: DesignTokens.ProgressBar.trackHeight)
                    .glassBackgroundEffect(in: Capsule())

                progressTrackLayer(
                    railWidth: overlayWidth,
                    playedWidth: DesignTokens.ProgressBar.thumbDiameter / 2 + width * progress,
                    scale: scale,
                    playedColor: DesignTokens.ProgressBar.playedColor,
                    unplayedColor: DesignTokens.ProgressBar.unplayedColor
                )

                progressTrackLayer(
                    railWidth: overlayWidth,
                    playedWidth: DesignTokens.ProgressBar.thumbDiameter / 2 + width * progress,
                    scale: scale,
                    playedColor: DesignTokens.ProgressBar.playedHoverColor,
                    unplayedColor: DesignTokens.ProgressBar.unplayedHoverColor
                )
                .enchronHoverOpacity(
                    active: 1,
                    inactive: 0,
                    in: hoverRevealGroup,
                    forcedActive: isDragging || isProgressHovered,
                    animation: DesignTokens.AnimationToken.selection,
                    macUsesLocalHover: true
                )
            }
            .frame(width: overlayWidth, height: DesignTokens.ProgressBar.trackHeight)
            .scaleEffect(y: scale)
            .animation(DesignTokens.PressFeedback.control.pressAnimation, value: scale)
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .allowsHitTesting(false)
    }

    private func progressTrackLayer(
        railWidth: CGFloat,
        playedWidth: CGFloat,
        scale: CGFloat,
        playedColor: Color,
        unplayedColor: Color
    ) -> some View {
        let visualHeight = DesignTokens.ProgressBar.trackHeight * scale
        let trackShape = RoundedRectangle(
            cornerSize: CGSize(
                width: visualHeight / 2,
                height: DesignTokens.ProgressBar.trackHeight / 2
            ),
            style: .continuous
        )

        return ZStack(alignment: .leading) {
            trackShape
                .fill(unplayedColor)
                .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
            trackShape
                .fill(playedColor)
                .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: playedWidth, height: DesignTokens.ProgressBar.trackHeight)
                }
        }
        .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
    }

    private var timeBubble: some View {
        let bubbleShape = RoundedRectangle(
            cornerRadius: DesignTokens.ProgressBar.timeBubbleRadius,
            style: .continuous
        )

        return HStack(spacing: DesignTokens.Spacing.xs) {
            Text(live?.elapsedLabel ?? "6:21").foregroundStyle(.primary)
            Text(live?.remainingLabel ?? "-7:54").foregroundStyle(.secondary)
        }
        .font(DesignTokens.Typography.monospacedDetail)
        .monospacedDigit()
        .padding(.horizontal, DesignTokens.ProgressBar.timeBubblePaddingH)
        .padding(.vertical, DesignTokens.ProgressBar.timeBubblePaddingV)
        .glassBackgroundEffect(in: bubbleShape)
    }

    private func scrubberControl(width: CGFloat) -> some View {
        Circle()
            .fill(.white)
            .overlay {
                Circle().strokeBorder(
                    DesignTokens.ProgressBar.thumbStroke,
                    lineWidth: DesignTokens.ProgressBar.thumbStrokeWidth
                )
            }
            .frame(width: DesignTokens.ProgressBar.thumbDiameter,
                   height: DesignTokens.ProgressBar.thumbDiameter)
            .accessibilityIdentifier("PlayerPanel-thumb")
            .accessibilityLabel("Playback position thumb")
            .enchronHoverContentShape(Circle())
            .enchronHoverEffect()
            .frame(width: DesignTokens.ProgressBar.hitHeight,
                   height: DesignTokens.ProgressBar.hitHeight)
            .enchronHoverContentShape(Circle())
            .enchronHoverActivation(in: hoverActivationGroup)
            .contentShape(Circle())
    }

    private func dragGesture(width: CGFloat, thumbX: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: DesignTokens.Stroke.regular)
            .onChanged { value in
                guard !isIgnoringDrag else { return }
                if !isDragging {
                    guard isThumbHit(value.startLocation, thumbX: thumbX) else {
                        isIgnoringDrag = true
                        return
                    }
                    // live 注入时进度起点取自当前播放位置(displayProgress),避免从陈旧
                    // 本地 @State 起跳;mock 时 displayProgress == progress,行为不变。
                    dragStartProgress = displayProgress
                    progress = displayProgress
                    beginScrubbing()
                }
                updateProgress(forTranslation: value.translation.width, width: width)
            }
            .onEnded { _ in
                if isDragging {
                    endScrubbing()
                    if live != nil {
                        // 锁存到目标值,跨过异步 seek 往返;live 追上后释放(见 body 的 onChange)。
                        pendingSeekTarget = progress
                    }
                    live?.onSeek(progress)
                }
                isIgnoringDrag = false
            }
    }

    private func beginScrubbing() {
        withAnimation(DesignTokens.PressFeedback.control.pressAnimation) { isDragging = true }
        scrubFeedbackTrigger += 1
    }

    private func endScrubbing() {
        withAnimation(DesignTokens.AnimationToken.selection) { isDragging = false }
        announcedBoundary = nil
    }

    private func progressValue(forTranslation translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return progress }
        return min(max(dragStartProgress + translationX / width, 0), 1)
    }

    private func updateProgress(forTranslation translationX: CGFloat, width: CGFloat) {
        let nextProgress = progressValue(forTranslation: translationX, width: width)
        updateBoundaryFeedback(for: nextProgress)
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { progress = nextProgress }
    }

    private func updateBoundaryFeedback(for nextProgress: CGFloat) {
        let boundary: ProgressBoundary?
        if nextProgress <= 0 {
            boundary = .minimum
        } else if nextProgress >= 1 {
            boundary = .maximum
        } else {
            boundary = nil
        }
        guard boundary != announcedBoundary else { return }
        announcedBoundary = boundary
        switch boundary {
        case .minimum: minimumBoundaryFeedbackTrigger += 1
        case .maximum: maximumBoundaryFeedbackTrigger += 1
        case nil: break
        }
    }

    private func openTimeline() {
        onInteraction()
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isDragging = false
            announcedBoundary = nil
        }
        timelineFeedbackTrigger += 1
        withAnimation(DesignTokens.AnimationToken.panelSpring) { timelineExpanded = true }
    }

    private func closeTimeline() {
        onInteraction()
        withAnimation(DesignTokens.AnimationToken.panelSpring) { timelineExpanded = false }
    }

    private func isThumbHit(_ location: CGPoint, thumbX: CGFloat) -> Bool {
        let thumbCenter = CGPoint(x: thumbX, y: DesignTokens.ProgressBar.hitHeight / 2)
        let hitRadius = DesignTokens.ProgressBar.hitHeight / 2
        let dx = location.x - thumbCenter.x
        let dy = location.y - thumbCenter.y
        return (dx * dx + dy * dy) <= (hitRadius * hitRadius)
    }
}
