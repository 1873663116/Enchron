import SwiftUI

// MARK: - Shared components used by the Design System review pages

// MARK: - Reusable controls

struct GlassCircleIconLabel: View {
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var visualSize: CGFloat = DesignTokens.Interactive.regular
    var targetSize: CGFloat = DesignTokens.Interactive.large
    var font: Font = DesignTokens.SymbolSize.control
    var accessibilityIdentifier: String?

    var body: some View {
        Image(systemName: systemName)
            .font(font)
            .foregroundStyle(iconColor)
            .frame(width: visualSize, height: visualSize)
            .clipShape(Circle())
            .glassBackgroundEffect(in: Circle())
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(.automatic)
            .padding(max((targetSize - visualSize) / 2, 0))
            .contentShape(Circle())
            .enchronPressFeedback(.icon)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-label-\(systemName)")
    }
}

struct GlassCircleIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var action: () -> Void = {}
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            GlassCircleIconLabel(
                systemName: systemName,
                accessibilityLabel: accessibilityLabel,
                iconColor: iconColor,
                accessibilityIdentifier: accessibilityIdentifier ?? "DesignPreview-button-\(systemName)"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-button-\(systemName)")
    }
}

extension View {
    func enchronTranslucentListContainer() -> some View {
        background(.regularMaterial, in: DesignTokens.ShapeToken.card)
            .clipShape(DesignTokens.ShapeToken.card)
            .overlay {
                DesignTokens.ShapeToken.card
                    .stroke(DesignTokens.Surface.divider, lineWidth: DesignTokens.Stroke.subtle)
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
        case automatic
        case menu(title: String, options: [MenuOption])
        case action(
            title: String,
            feedback: String?,
            systemName: String?,
            role: ActionRole,
            action: () -> Void
        )
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let systemName: String
        /// Descriptive copy revealed when the row expands. `nil` keeps the row a
        /// plain tappable entry that fires `action` instead of disclosing.
        var detail: String? = nil
        var expansion: ExpansionOrigin = .top
        var accessory: Accessory = .automatic
        var action: () -> Void = {}

        init(
            id: String? = nil,
            title: String,
            systemName: String,
            detail: String? = nil,
            expansion: ExpansionOrigin = .top,
            accessory: Accessory = .automatic,
            action: @escaping () -> Void = {}
        ) {
            self.id = id ?? "\(systemName)-\(title)"
            self.title = title
            self.systemName = systemName
            self.detail = detail
            self.expansion = expansion
            self.accessory = accessory
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
                    detail: item.detail,
                    expansion: item.expansion,
                    accessory: item.accessory,
                    cornerRadius: cornerRadius,
                    index: index,
                    count: items.count,
                    hoverNamespace: hoverNamespace,
                    action: item.action
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: groupShape)
        .clipShape(groupShape)
        .overlay {
            groupShape
                .stroke(DesignTokens.Surface.divider, lineWidth: DesignTokens.Stroke.subtle)
        }
        .contentShape(groupShape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct SettingListGroupRow: View {
    let title: String
    let systemName: String
    var detail: String?
    var expansion: SettingListGroup.ExpansionOrigin = .top
    var accessory: SettingListGroup.Accessory = .automatic
    let cornerRadius: CGFloat
    let index: Int
    let count: Int
    var hoverNamespace: Namespace.ID?
    var action: () -> Void = {}

    @State private var isExpanded = false
    @State private var selectedMenuTitle: String?
    @State private var feedbackTitle: String?
    @State private var feedbackResetID = UUID()

    private var isFirst: Bool { index == 0 }
    private var isLast: Bool { index == count - 1 }
    private var isExpandable: Bool { detail != nil }
    private var showsDivider: Bool { !isLast }
    private var usesWholeRowButton: Bool {
        if case .automatic = accessory {
            return true
        }
        return false
    }

    // Concentric corner rounding: round only the outer corners (matching the
    // container clip) so the highlight aligns with the group edge and sits
    // square against the separators on its inner edges.
    private var highlightShape: UnevenRoundedRectangle {
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? cornerRadius : 0,
            bottomLeadingRadius: isLast ? cornerRadius : 0,
            bottomTrailingRadius: isLast ? cornerRadius : 0,
            topTrailingRadius: isFirst ? cornerRadius : 0,
            style: .continuous
        )
    }

    /// The hover-effect group owned by the row at `rowIndex`. A row *activates*
    /// its own group when gazed; a separator *follows* the groups of the rows
    /// above and below it, so it fades whenever either neighbour is highlighted.
    private func rowGroup(_ rowIndex: Int, _ behavior: HoverEffectGroup.Behavior) -> HoverEffectGroup? {
        guard let hoverNamespace else { return nil }
        return HoverEffectGroup(id: "settingListRow\(rowIndex)", in: hoverNamespace, behavior: behavior)
    }

    @ViewBuilder
    var body: some View {
        // A real `Button` owns the tap — reliable on visionOS and carrying the
        // system button trait — while `.buttonStyle(.plain)` leaves all visuals
        // to the gaze hover stack below (the same plain-button + custom
        // hoverEffect split the reference `SettingsAccessoryButton` uses). The
        // whole row is the hit target; the chevron is a pure indicator.
        if usesWholeRowButton {
            Button(action: handleTap) {
                rowSurface
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isExpandable ? (isExpanded ? "Expanded" : "Collapsed") : "")
        } else {
            rowSurface
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
        }
    }

    private var rowSurface: some View {
        VStack(spacing: 0) {
            rowContent

            if isExpanded, let detail {
                expandedDetail(detail)
                    .transition(expansionTransition)
            }

        }
        .frame(maxWidth: .infinity)
        .contentShape(.hoverEffect, highlightShape)
        .contentShape(.interaction, highlightShape)
        .hoverEffect(.highlight)
        .hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.006 : 1.0)
        }
        // No-op trigger: gazing this row activates its own group so the
        // separators on both sides (which follow this group) fade in sync
        // with the highlight — same system-composited phase, same timing.
        .hoverEffect(in: rowGroup(index, .activatesGroup)) { effect, _, _ in effect }
        .background(alignment: .bottom) {
            if showsDivider {
                SettingListGroupDivider()
                    .padding(.leading, DesignTokens.Spacing.lg)
                    .padding(.trailing, DesignTokens.Spacing.lg)
                    // Follows both bordering rows: row `index` (above) and
                    // row `index + 1` (below). Either one's hover fades it.
                    .hoverEffect(in: rowGroup(index, .followsGroup)) { effect, isActive, _ in
                        effect.opacity(isActive ? 0 : 1)
                    }
                    .hoverEffect(in: rowGroup(index + 1, .followsGroup)) { effect, isActive, _ in
                        effect.opacity(isActive ? 0 : 1)
                    }
            }
        }
        // Drives the height change of this row and the rows it pushes down with
        // the same bouncy spring the detail panel animates in on.
        .animation(DesignTokens.AnimationToken.selection, value: isExpanded)
    }

    private var rowContent: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: systemName)
                .font(DesignTokens.SymbolSize.selectionHeaderIcon)
                .foregroundStyle(.secondary)
                .frame(width: DesignTokens.Interactive.compact)

            Text(title)
                .font(DesignTokens.Typography.selectionHeader)
                .foregroundStyle(DesignTokens.Surface.selectionHeaderText)

            Spacer(minLength: DesignTokens.Spacing.lg)

            trailingAccessory
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: DesignTokens.Interactive.rowHeight)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch accessory {
        case .automatic:
            Image(systemName: "chevron.right")
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
                // Expandable rows rotate the chevron to point down when open;
                // plain navigation rows keep it static as a forward affordance.
                .rotationEffect(isExpandable && isExpanded ? .degrees(90) : .zero)

        case .menu(let title, let options):
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
                    systemName: "chevron.up.chevron.down"
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

    /// Mirrors the `SettingsDetailRow` disclosure motion: a small anchored scale
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
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.highlight)
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
    var iconColor: Color = .secondary
    var accessibilityIdentifier: String = "DesignPreview-menu-sort"

    var body: some View {
        Menu {
            Section("Sort By") {
                sortKeyButton(.name, title: "Name")
                sortKeyButton(.modifiedDate, title: "Date Modified")
                sortKeyButton(.size, title: "Size")
            }

            Menu("Order") {
                sortOrderButton(.ascending, title: "Ascending")
                sortOrderButton(.descending, title: "Descending")
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

    private func sortKeyButton(_ key: SortMenuKey, title: String) -> some View {
        Button {
            sortKey = key
        } label: {
            Label(title, systemImage: sortKey == key ? "checkmark" : "")
        }
    }

    private func sortOrderButton(_ order: SortMenuOrder, title: String) -> some View {
        Button {
            sortOrder = order
        } label: {
            Label(title, systemImage: sortOrder == order ? "checkmark" : "")
        }
    }
}

struct GlassCapsuleIconLabelButton: View {
    let title: String
    let systemName: String
    let accessibilityLabel: String
    var iconColor: Color = .white
    var minWidth: CGFloat = DesignTokens.Interactive.regular * 2
    var action: () -> Void = {}
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(iconColor)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minWidth: minWidth, minHeight: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
        .padding(.vertical, (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2)
        .contentShape(Capsule())
        .enchronPressFeedback(.control)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignPreview-button-\(title)")
    }
}

struct NavBackForwardCapsuleControl: View {
    var iconColor: Color = .white
    var trailingOpacity: Double = 0.65
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var accessibilityIdentifier: String = "DesignPreview-control-navBackForward"
    var accessibilityLabel: String = "Back and Forward"

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
    var iconColor: Color = .white
    var unselectedOpacity: Double = 0.45
    var accessibilityIdentifier: String = "DesignPreview-control-viewMode"
    var accessibilityLabel: String = "View Mode"

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

struct VideoCardLarge: View {
    @Namespace private var hoverNamespace

    let title: String
    let fileSize: String
    let duration: String
    var badges: [String] = []
    var width: CGFloat = DesignTokens.Card.gridMin
    // Future Settings entry: false keeps the grid clean; true allows thumbnail info to appear on hover.
    var showsSupplementaryInfo = true

    private var hoverActivationGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "video-card-thumbnail-info",
            in: hoverNamespace,
            behavior: .activatesGroup
        )
    }

    private var hoverRevealGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "video-card-thumbnail-info",
            in: hoverNamespace,
            behavior: .followsGroup
        )
    }

    var body: some View {
        let shape = DesignTokens.ShapeToken.card
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail placeholder — in real app this is the video frame
                shape
                    .fill(DesignTokens.Surface.elevated)
                    .frame(height: DesignTokens.Card.thumbnailHeight)

                if showsSupplementaryInfo {
                    videoThumbnailInfo
                }
            }
            .frame(height: DesignTokens.Card.thumbnailHeight)
            .clipShape(shape)
            .glassBackgroundEffect(in: shape)
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.highlight, in: hoverActivationGroup)

            Text(title)
                .font(DesignTokens.Typography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Card.paddingH)
            .padding(.vertical, DesignTokens.Card.paddingV)
        }
        .frame(width: width)
        .contentShape(shape)
        .enchronPressFeedback(.card)
    }

    private var videoThumbnailInfo: some View {
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
        .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
            effect.animation(DesignTokens.AnimationToken.controlsTransition) {
                $0.opacity(isActive ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func thumbnailBadge(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.badge)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .enchronGlassBadge()
    }

    private func thumbnailMetadata(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.secondary)
    }
}

struct FolderCard: View {
    @Namespace private var hoverNamespace

    let title: String
    let count: Int
    var width: CGFloat = DesignTokens.Card.gridMin
    // Future Settings entry: false keeps the grid clean; true allows thumbnail info to appear on hover.
    var showsSupplementaryInfo = true

    private var hoverActivationGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "folder-card-thumbnail-info",
            in: hoverNamespace,
            behavior: .activatesGroup
        )
    }

    private var hoverRevealGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "folder-card-thumbnail-info",
            in: hoverNamespace,
            behavior: .followsGroup
        )
    }

    var body: some View {
        let shape = DesignTokens.ShapeToken.card
        VStack(alignment: .leading, spacing: 0) {
            shape
                .fill(DesignTokens.Surface.elevated)
                .frame(height: DesignTokens.Card.thumbnailHeight)
                .overlay(alignment: .center) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.tertiary)
                }
                .overlay(alignment: .bottomLeading) {
                    if showsSupplementaryInfo {
                        folderThumbnailInfo
                    }
                }
                .clipShape(shape)
                .glassBackgroundEffect(in: shape)
                .contentShape(.hoverEffect, shape)
                .hoverEffect(.highlight, in: hoverActivationGroup)

            Text(title)
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Card.paddingH)
                .padding(.vertical, DesignTokens.Card.paddingV)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: width)
        .contentShape(shape)
        .enchronPressFeedback(.card)
    }

    private var folderThumbnailInfo: some View {
        HStack {
            thumbnailMetadata("\(count) items")
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
            effect.animation(DesignTokens.AnimationToken.controlsTransition) {
                $0.opacity(isActive ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func thumbnailMetadata(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.Typography.metadata)
            .foregroundStyle(.primary)
    }
}

struct SceneCardMedium: View {
    let icon: String
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: icon)
                .font(DesignTokens.SymbolSize.feature)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 100, height: 80)
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(DesignTokens.Spacing.sm)
        .overlay(
            isSelected
                ? RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: DesignTokens.Stroke.bold)
                : nil
        )
        .enchronGlassCard()
        .enchronPressFeedback(.card)
    }
}

struct FeaturedScene: Identifiable {
    let id: String
    let imageName: String
    let title: String
    let sceneNumber: String
    let quote: String
    let mode: String
    let atmosphere: String

    static let fixtures: [FeaturedScene] = [
        .init(
            id: "snow-village",
            imageName: "SceneFeatureCard",
            title: "Snow Village",
            sceneNumber: "Scene 01",
            quote: "\"A bright winter morning opens into a quiet alpine town.\"",
            mode: "Spatial cinema",
            atmosphere: "Snowfield / clear daylight"
        ),
        .init(
            id: "dune-observatory",
            imageName: "SceneFeatureDesert",
            title: "Dune Observatory",
            sceneNumber: "Scene 02",
            quote: "\"A gold horizon turns the theatre into a quiet instrument.\"",
            mode: "Observatory cinema",
            atmosphere: "Desert / amber dusk"
        ),
        .init(
            id: "neon-canopy",
            imageName: "SceneFeatureNeonCity",
            title: "Neon Canopy",
            sceneNumber: "Scene 03",
            quote: "\"Rain and city light fold into a private rooftop screen.\"",
            mode: "Night lounge",
            atmosphere: "Neon / reflective rain"
        ),
        .init(
            id: "forest-shrine",
            imageName: "SceneFeatureForestShrine",
            title: "Forest Shrine",
            sceneNumber: "Scene 04",
            quote: "\"The woods dim the world without closing it in.\"",
            mode: "Ambient cinema",
            atmosphere: "Moss / morning mist"
        ),
        .init(
            id: "ocean-temple",
            imageName: "SceneFeatureOceanTemple",
            title: "Ocean Temple",
            sceneNumber: "Scene 05",
            quote: "\"Light falls through water and softens every edge.\"",
            mode: "Deep cinema",
            atmosphere: "Coral / turquoise depth"
        ),
        .init(
            id: "orbital-garden",
            imageName: "SceneFeatureOrbitalGarden",
            title: "Orbital Garden",
            sceneNumber: "Scene 06",
            quote: "\"A living station holds the planet in the corner of your eye.\"",
            mode: "Spatial cinema",
            atmosphere: "Orbit / luminous green"
        ),
        .init(
            id: "dream-cinema",
            imageName: "SceneFeatureCinema",
            title: "Dream Cinema",
            sceneNumber: "Scene 07",
            quote: "\"Projector light turns the hall into a warm private ritual.\"",
            mode: "Classic theatre",
            atmosphere: "Velvet / brass glow"
        )
    ]
}

struct FeaturedSceneCard: View {
    var scene: FeaturedScene = .fixtures[0]
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
            sceneInfoPanel
            topControls
        }
        .frame(width: Metrics.cardWidth, height: Metrics.cardHeight)
        .clipShape(shape)
        .glassBackgroundEffect(in: shape)
        .overlay {
            shape.strokeBorder(DesignTokens.Surface.overlay, lineWidth: DesignTokens.Stroke.regular)
        }
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DesignPreview-FeaturedSceneCard")
        .accessibilityLabel("Featured scene card, \(scene.title)")
    }

    private var clampedDetailVisibility: CGFloat {
        max(0, min(1, detailVisibility))
    }

    private var clampedAtmosphericFade: CGFloat {
        max(0, min(1, atmosphericFade))
    }

    private var backgroundImage: some View {
        Image(scene.imageName)
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
                    accessibilityIdentifier: "DesignPreview-FeaturedSceneCard-button-return"
                )
                Spacer()
                GlassCircleIconButton(
                    systemName: "arrow.up.left.and.arrow.down.right",
                    accessibilityLabel: "Expand scene",
                    action: onExpand,
                    accessibilityIdentifier: "DesignPreview-FeaturedSceneCard-button-expand"
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

    private var sceneInfoPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(scene.title)
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(.white)
                Spacer(minLength: DesignTokens.Spacing.md)
                Text(scene.sceneNumber)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text(scene.quote)
                .font(.title3)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Mode: \(scene.mode)")
                Text("Atmosphere: \(scene.atmosphere)")
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

struct SceneCardCarousel: View {
    var scenes: [FeaturedScene] = FeaturedScene.fixtures
    var onReturn: () -> Void = {}

    @State private var scrollPosition: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0
    @State private var isDragging = false
    @State private var isSettling = false
    @State private var detailsVisible = true
    @State private var motionGeneration = 0
    @State private var detailRevealTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if scenes.isEmpty {
                EmptyView()
            } else {
                ForEach(renderItems) { item in
                    FeaturedSceneCard(
                        scene: item.scene,
                        detailVisibility: interactionDetailVisibility(for: item.visualPosition),
                        atmosphericFade: atmosphericFade(for: item.visualPosition),
                        onReturn: onReturn,
                        onExpand: {},
                        onMore: {}
                    )
                    .allowsHitTesting(abs(item.visualPosition) < Metrics.centerHitTestingDistance)
                    .opacity(Double(cardOpacity(for: item.visualPosition)))
                    .offset(z: zOffset(for: item.visualPosition))
                    .offset(x: xOffset(for: item.visualPosition), y: yOffset(for: item.visualPosition))
                    .zIndex(zIndex(for: item.visualPosition))
                    .accessibilityHidden(abs(item.visualPosition) >= Metrics.centerHitTestingDistance)
                }
            }
        }
        .frame(width: Metrics.stageWidth, height: Metrics.stageHeight)
        .frame(depth: Metrics.stageDepth)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .accessibilityIdentifier("DesignPreview-SceneCardCarousel")
    }

    private var renderItems: [RenderItem] {
        scenes.indices.compactMap { index in
            let visualPosition = visualPosition(for: index)
            guard abs(visualPosition) <= activeRenderCardDistance else {
                return nil
            }

            return RenderItem(
                visualPosition: visualPosition,
                scene: scenes[index]
            )
        }
    }

    private var activeRenderCardDistance: CGFloat {
        isDragging || isSettling ? Metrics.motionRenderCardDistance : Metrics.stableRenderCardDistance
    }

    private var currentScrollPosition: CGFloat {
        guard !scenes.isEmpty else { return 0 }
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
        guard !scenes.isEmpty else { return 0 }
        let sceneCount = CGFloat(scenes.count)
        let rawPosition = CGFloat(index) - currentScrollPosition
        return rawPosition - (rawPosition / sceneCount).rounded() * sceneCount
    }

    private func normalizedScrollPosition(_ position: CGFloat) -> CGFloat {
        guard !scenes.isEmpty else { return 0 }
        let sceneCount = CGFloat(scenes.count)
        let remainder = position.truncatingRemainder(dividingBy: sceneCount)
        return remainder >= 0 ? remainder : remainder + sceneCount
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
        static let stageWidth: CGFloat = DesignTokens.SceneCarousel.stageWidth
        static let stageHeight: CGFloat = DesignTokens.SceneCarousel.stageHeight
        static let stageDepth: CGFloat = DesignTokens.SceneCarousel.stageDepth
        static let dragDistance: CGFloat = DesignTokens.SceneCarousel.dragDistance
        static let snapThreshold: CGFloat = DesignTokens.SceneCarousel.snapThreshold
        static let maximumPredictedStepLead: CGFloat = DesignTokens.SceneCarousel.maximumPredictedStepLead
        static let maximumStepPerGesture: CGFloat = DesignTokens.SceneCarousel.maximumStepPerGesture
        static let detailRevealDelayNanoseconds = DesignTokens.SceneCarousel.detailRevealDelayNanoseconds
        static let detailRevealDelayPerStepNanoseconds =
            DesignTokens.SceneCarousel.detailRevealDelayPerStepNanoseconds
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
        static let centerCardGap: CGFloat = DesignTokens.SceneCarousel.centerCardGap
        static let outerCardGap: CGFloat = DesignTokens.SceneCarousel.outerCardGap
        static let sideCardYOffset: CGFloat = DesignTokens.SceneCarousel.sideCardYOffset
        static let centerDepthOffset: CGFloat = DesignTokens.SceneCarousel.centerDepthOffset
        static let sideDepthOffset: CGFloat = DesignTokens.SceneCarousel.sideDepthOffset
        static let atmosphericFadeStart: CGFloat = DesignTokens.SceneCarousel.atmosphericFadeStart
        static let atmosphericFadeEnd: CGFloat = DesignTokens.SceneCarousel.atmosphericFadeEnd
        static let atmosphericFadeMaxOpacity: CGFloat = DesignTokens.SceneCarousel.atmosphericFadeMaxOpacity
        static let detailRevealStart: CGFloat = DesignTokens.SceneCarousel.detailRevealStart
        static let detailRevealComplete: CGFloat = DesignTokens.SceneCarousel.detailRevealComplete
    }

    private struct RenderItem: Identifiable {
        let visualPosition: CGFloat
        let scene: FeaturedScene

        var id: String {
            scene.id
        }
    }
}

// MARK: - Row items

struct FileListRow: View {
    let icon: String
    let title: String
    let metadata: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title).font(.body)
            Spacer()
            Text(metadata)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
        .enchronPressFeedback(.row)
    }
}

struct VideoListRow: View {
    @Namespace private var hoverNamespace

    let title: String
    let fileSize: String
    let duration: String
    var badges: [String] = []
    var showsDivider = false

    private var hoverActivationGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "video-list-row-info",
            in: hoverNamespace,
            behavior: .activatesGroup
        )
    }

    private var hoverRevealGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "video-list-row-info",
            in: hoverNamespace,
            behavior: .followsGroup
        )
    }

    var body: some View {
        let shape = DesignTokens.ShapeToken.element

        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "film")
                .font(.body)
                .frame(width: DesignTokens.Spacing.xl)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: DesignTokens.Spacing.lg)

            metadataRegion
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: DesignTokens.Interactive.rowHeight)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(DesignTokens.Surface.divider)
                    .frame(height: DesignTokens.Stroke.regular)
                    .padding(.horizontal, DesignTokens.Spacing.xs)
            }
        }
        .contentShape(.hoverEffect, shape)
        .contentShape(shape)
        .hoverEffect(.highlight, in: hoverActivationGroup)
        .enchronPressFeedback(.row)
        .accessibilityLabel(title)
    }

    private var metadataRegion: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if !badges.isEmpty {
                Text(badges.joined(separator: " · "))
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(DesignTokens.Surface.accessoryText)
            }

            Text(fileSize)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.accessoryText)

            Text(duration)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
        }
        .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
            effect.animation(DesignTokens.AnimationToken.controlsTransition) {
                $0.opacity(isActive ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

struct MenuItemRow: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .rotationEffect(isExpanded ? .degrees(90) : .zero)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
        .enchronPressFeedback(.row)
    }
}

struct SubMenuItemRow: View {
    let title: String
    let isChecked: Bool

    var body: some View {
        HStack {
            Text(title).font(.body)
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.Interactive.rowHeight)
        .enchronGlassMenuItem()
        .enchronPressFeedback(.row)
    }
}

// MARK: - Small elements

struct MockToggle: View {
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
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
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
/// `CenterSlider` is the macro component; a `CenterDetentSlider` specialization
/// can be split out later if a non-detented (continuous) variant is needed.
struct CenterSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = -5...5
    let leadingSystemImage: String
    let trailingSystemImage: String
    var accessibilityLabel: String = "Center slider"
    var accessibilityIdentifier: String = "DesignPreview-CenterSlider"

    // Value at the moment the drag began; the live snap measures the finger's
    // translation against this origin so the knob lands on whole detents only.
    @State private var dragStartValue: Int?
    @State private var isDragging = false

    // EXPLORATORY: track-bar dimensions are not yet promoted to DesignTokens.
    // Knob (26) and track height (30) mirror the existing toggle for reuse;
    // promoting these to shared tokens needs a separate human decision.
    private let trackWidth: CGFloat = 450
    private let trackHeight: CGFloat = 30
    private let knobSize: CGFloat = 26
    private let dotSize: CGFloat = 4

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
                .foregroundStyle(.secondary)

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
                .foregroundStyle(.secondary)
        }
        .font(.body)
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

    private var track: some View {
        Capsule()
            .fill(DesignTokens.Surface.elevated)
            .frame(width: trackWidth, height: trackHeight)
            .overlay(alignment: .center) { litSegment }
            .overlay(alignment: .center) { knob.offset(x: knobOffset) }
            .clipShape(Capsule())
            .glassBackgroundEffect(in: Capsule())
            // Gesture lives on the *static* track, never on the moving knob, so
            // the drag coordinate space stays fixed and the offset can't feed
            // back on itself (the source of the earlier jitter). Hover mirrors
            // the toggle: the whole capsule highlights on gaze.
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
            .gesture(dragGesture)
    }

    /// The accent fill running from the centre origin to the knob — gives the
    /// drag a direction + magnitude cue. Uses the same accent as the toggle's
    /// "on" capsule, and fills the *full* track height so the knob sits inside a
    /// 2pt accent ring just like the toggle. Its knob-facing cap is extended by
    /// the track radius so the cap shares the knob's centre, leaving no seam.
    /// Hidden at the centre origin (no offset → nothing lit).
    ///
    /// The accent capsule carries its own `glassBackgroundEffect`, mirroring the
    /// toggle's `fill(accent) + glassBackgroundEffect(in: Capsule())`: the glass
    /// rim/specular then follows the lit shape itself, instead of the accent
    /// reading as flat paint laid over the track's glass.
    private var litSegment: some View {
        let radius = trackHeight / 2
        return Capsule()
            .fill(DesignTokens.Theme.accent)
            .frame(width: abs(knobOffset) + radius, height: trackHeight)
            .glassBackgroundEffect(in: Capsule())
            .offset(x: (knobOffset + (knobOffset >= 0 ? radius : -radius)) / 2)
            .opacity(abs(knobOffset) > 0.5 ? 1 : 0)
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .frame(width: knobSize, height: knobSize)
            .scaleEffect(isDragging ? DesignTokens.PressFeedback.control.pressedScale : 1.0)
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

struct MockBreadcrumb: View {
    let path: [String]
    let onSelectLevel: (Int) -> Void

    init(
        path: [String] = ["Local Storage", "Movies"],
        onSelectLevel: @escaping (Int) -> Void = { _ in }
    ) {
        self.path = path
        self.onSelectLevel = onSelectLevel
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            ForEach(Array(path.enumerated()), id: \.offset) { index, node in
                Button(node) {
                    onSelectLevel(index)
                }
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(.secondary)
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.lift)
                .contentShape(Capsule())

                if index < path.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
        }
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
            ForEach(Array(path.enumerated()), id: \.offset) { index, _ in
                Button {
                    onSelectLevel(index)
                } label: {
                    Label(pathPrefix(through: index), systemImage: index == path.count - 1 ? "checkmark" : "")
                }
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
        .accessibilityLabel(currentFolder)
    }

    private func pathPrefix(through index: Int) -> String {
        path.prefix(index + 1).joined(separator: " / ")
    }
}

struct SearchInputCapsule: View {
    @Binding var text: String
    var placeholder = "Search"
    var width: CGFloat = DesignTokens.Card.gridMin
    var accessibilityIdentifier = "DesignPreview-input-search"

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
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .hoverEffectDisabled()
                .onTapGesture(perform: activateInput)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(width: width, height: DesignTokens.Interactive.regular)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: Capsule())
        .contentShape(.hoverEffect, Capsule())
        .hoverEffect(.automatic)
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

struct FilterPillBar: View {
    let filters: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(filters, id: \.self) { filter in
                Button {
                    withAnimation(DesignTokens.AnimationToken.selection) {
                        selection = filter
                    }
                } label: {
                    Text(filter)
                        .font(.body)
                        .foregroundStyle(selection == filter ? .primary : .secondary)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .background(selection == filter ? DesignTokens.Surface.selected : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .enchronGlassPill()
                .contentShape(.hoverEffect, Capsule())
                .hoverEffect(.automatic)
            }
        }
    }
}

struct SourceSidebarRow: View {
    let icon: String
    let title: String
    var isSelected = false
    var isEnabled = true
    var isOnline = false
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

            if isOnline {
                Circle()
                    .fill(isSelected ? DesignTokens.Theme.accent : .green)
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

struct PlayerProgressBar: View {
    var timelineResetToken = 0

    @Namespace private var hoverNamespace
    @State private var progress: CGFloat = 0.45
    @State private var isDragging = false
    @State private var isIgnoringDrag = false
    @State private var dragStartProgress: CGFloat = 0.45
    @State private var isTimelineExpanded = false
    @State private var scrubFeedbackTrigger = 0
    @State private var minimumBoundaryFeedbackTrigger = 0
    @State private var maximumBoundaryFeedbackTrigger = 0
    @State private var timelineFeedbackTrigger = 0
    @State private var announcedBoundary: ProgressBoundary? = nil
    @State private var timelinePixelsPerSecond = DesignTokens.PrecisionTimeline.initialPixelsPerSecond

    private enum ProgressBoundary {
        case minimum
        case maximum
    }

    private var trackScale: CGFloat {
        isDragging
            ? 1
            : DesignTokens.ProgressBar.inactiveScale
    }

    private var hoverActivationGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "progress-bar-reveal",
            in: hoverNamespace,
            behavior: .activatesGroup
        )
    }

    private var hoverRevealGroup: HoverEffectGroup {
        HoverEffectGroup(
            id: "progress-bar-reveal",
            in: hoverNamespace,
            behavior: .followsGroup
        )
    }

    var body: some View {
        let overlayWidth = DesignTokens.ProgressBar.previewWidth
        let width = max(overlayWidth - DesignTokens.ProgressBar.thumbDiameter, 0)
        let clampedProgress = min(max(progress, 0), 1)
        let thumbX = DesignTokens.ProgressBar.thumbDiameter / 2 + clampedProgress * width
        let containerWidth = currentContainerWidth
        let containerHeight = currentContainerHeight

        ZStack(alignment: .bottomLeading) {
            expandedTimelineDismissLayer(
                containerWidth: containerWidth,
                containerHeight: containerHeight
            )

            if !isTimelineExpanded {
                progressBarBody(
                    width: width,
                    clampedProgress: clampedProgress,
                    thumbX: thumbX,
                    overlayWidth: overlayWidth
                )
                .offset(x: (containerWidth - overlayWidth) / 2)
                .transition(.opacity)
            }

            expandedTimeline(containerWidth: containerWidth)
                .zIndex(2)
        }
        .frame(width: containerWidth, height: containerHeight, alignment: .bottomLeading)
        .animation(DesignTokens.AnimationToken.panelSpring, value: isTimelineExpanded)
        .sensoryFeedback(.press(.slider), trigger: scrubFeedbackTrigger)
        .sensoryFeedback(.selection(.minimum), trigger: minimumBoundaryFeedbackTrigger)
        .sensoryFeedback(.selection(.maximum), trigger: maximumBoundaryFeedbackTrigger)
        .sensoryFeedback(.selection(.on), trigger: timelineFeedbackTrigger)
        .accessibilityIdentifier("DesignPreview-PlayerProgressBar")
        .accessibilityLabel("Playback progress")
        .onChange(of: timelineResetToken) {
            resetTimelinePresentation()
        }
    }

    private var currentContainerWidth: CGFloat {
        isTimelineExpanded
            ? max(DesignTokens.ProgressBar.previewWidth, DesignTokens.PrecisionTimeline.expandedWidth)
            : DesignTokens.ProgressBar.previewWidth
    }

    private var currentContainerHeight: CGFloat {
        isTimelineExpanded
            ? DesignTokens.PrecisionTimeline.expandedHeight
            : DesignTokens.ProgressBar.hitHeight
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
                .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
                    effect.animation(DesignTokens.AnimationToken.selection) {
                        $0.opacity(isActive || isDragging ? 1.0 : 0.0)
                    }
                }
                .allowsHitTesting(false)

            scrubberControl(width: width)
                .position(
                    x: thumbX,
                    y: DesignTokens.ProgressBar.hitHeight / 2
                )
        }
        .frame(width: overlayWidth, height: DesignTokens.ProgressBar.hitHeight)
        .contentShape(.interaction, Capsule())
        .gesture(dragGesture(width: width, thumbX: thumbX))
    }

    private func hoverCarrier(width: CGFloat) -> some View {
        Capsule()
            .fill(DesignTokens.ProgressBar.hoverCarrierFill)
            .frame(width: width, height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(in: hoverActivationGroup) { effect, isActive, _ in
                effect.animation(DesignTokens.AnimationToken.selection) {
                    $0.opacity(isActive ? 1.0 : DesignTokens.ProgressBar.hoverCarrierInactiveOpacity)
                }
            }
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
                .hoverEffect(in: hoverRevealGroup) { effect, isActive, _ in
                    effect.animation(DesignTokens.AnimationToken.selection) {
                        $0.opacity(isActive || isDragging ? 1.0 : 0.0)
                    }
                }
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
        let shape = RoundedRectangle(
            cornerSize: CGSize(
                width: visualHeight / 2,
                height: DesignTokens.ProgressBar.trackHeight / 2
            ),
            style: .continuous
        )

        return ZStack(alignment: .leading) {
            shape
                .fill(unplayedColor)
                .frame(width: railWidth, height: DesignTokens.ProgressBar.trackHeight)
            shape
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
        let shape = RoundedRectangle(
            cornerRadius: DesignTokens.ProgressBar.timeBubbleRadius,
            style: .continuous
        )

        return HStack(spacing: DesignTokens.Spacing.xs) {
            Text("6:21")
                .foregroundStyle(.primary)
            Text("-7:54")
                .foregroundStyle(.secondary)
        }
            .font(DesignTokens.Typography.monospacedDetail)
            .monospacedDigit()
            .padding(.horizontal, DesignTokens.ProgressBar.timeBubblePaddingH)
            .padding(.vertical, DesignTokens.ProgressBar.timeBubblePaddingV)
            .glassBackgroundEffect(in: shape)
    }

    private func scrubberThumbVisual() -> some View {
        Circle()
            .fill(.white)
            .overlay {
                Circle()
                    .strokeBorder(
                        DesignTokens.ProgressBar.thumbStroke,
                        lineWidth: DesignTokens.ProgressBar.thumbStrokeWidth
                    )
            }
            .frame(width: DesignTokens.ProgressBar.thumbDiameter,
                   height: DesignTokens.ProgressBar.thumbDiameter)
    }

    private func scrubberThumb() -> some View {
        scrubberThumbVisual()
            .accessibilityIdentifier("DesignPreview-PlayerProgressBar-thumb")
            .accessibilityLabel("Playback position thumb")
    }

    private func scrubberControl(width: CGFloat) -> some View {
        scrubberThumb()
            .contentShape(.hoverEffect, Circle())
            .hoverEffect()
            .frame(width: DesignTokens.ProgressBar.hitHeight,
                   height: DesignTokens.ProgressBar.hitHeight)
            .contentShape(.hoverEffect, Circle())
            .hoverEffect(in: hoverActivationGroup) { effect, isActive, _ in
                effect.animation(DesignTokens.AnimationToken.selection) {
                    $0.opacity(1.0)
                }
            }
            .contentShape(Circle())
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        openTimeline()
                    }
            )
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
                    dragStartProgress = progress
                    beginScrubbing()
                }
                updateProgress(forTranslation: value.translation.width, width: width)
            }
            .onEnded { _ in
                if isDragging {
                    endScrubbing()
                }
                isIgnoringDrag = false
            }
    }

    private func beginScrubbing() {
        withAnimation(DesignTokens.PressFeedback.control.pressAnimation) {
            isDragging = true
        }
        scrubFeedbackTrigger += 1
    }

    private func endScrubbing() {
        withAnimation(DesignTokens.AnimationToken.selection) {
            isDragging = false
        }
        announcedBoundary = nil
    }

    private func progress(forTranslation translationX: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return progress }
        return min(max(dragStartProgress + translationX / width, 0), 1)
    }

    private func updateProgress(forTranslation translationX: CGFloat, width: CGFloat) {
        let nextProgress = progress(forTranslation: translationX, width: width)
        updateBoundaryFeedback(for: nextProgress)

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            progress = nextProgress
        }
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
        case .minimum:
            minimumBoundaryFeedbackTrigger += 1
        case .maximum:
            maximumBoundaryFeedbackTrigger += 1
        case nil:
            break
        }
    }

    private func openTimeline() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isDragging = false
            announcedBoundary = nil
        }

        timelineFeedbackTrigger += 1
        withAnimation(DesignTokens.AnimationToken.panelSpring) {
            isTimelineExpanded = true
        }
    }

    private func resetTimelinePresentation() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isTimelineExpanded = false
            isDragging = false
            isIgnoringDrag = false
            announcedBoundary = nil
        }
    }

    private func isThumbHit(_ location: CGPoint, thumbX: CGFloat) -> Bool {
        let thumbCenter = CGPoint(
            x: thumbX,
            y: DesignTokens.ProgressBar.hitHeight / 2
        )
        let hitRadius = DesignTokens.ProgressBar.hitHeight / 2
        let dx = location.x - thumbCenter.x
        let dy = location.y - thumbCenter.y
        return (dx * dx + dy * dy) <= (hitRadius * hitRadius)
    }

    @ViewBuilder
    private func expandedTimelineDismissLayer(
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        if isTimelineExpanded {
            Rectangle()
                .fill(.clear)
                .frame(width: containerWidth, height: containerHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DesignTokens.AnimationToken.panelSpring) {
                        isTimelineExpanded = false
                    }
                }
                .zIndex(1)
        }
    }

    @ViewBuilder
    private func expandedTimeline(containerWidth: CGFloat) -> some View {
        if isTimelineExpanded {
            PrecisionTimelineView(
                currentTime: timelineCurrentTime,
                pixelsPerSecond: $timelinePixelsPerSecond,
                duration: DesignTokens.PrecisionTimeline.previewDuration,
                framesPerSecond: DesignTokens.PrecisionTimeline.previewFrameRate
            )
            .frame(
                width: DesignTokens.PrecisionTimeline.expandedWidth,
                height: DesignTokens.PrecisionTimeline.expandedHeight
            )
            .transition(
                .opacity
                    .combined(with: .offset(x: 0, y: DesignTokens.Spacing.sm))
            )
            .offset(x: (containerWidth - DesignTokens.PrecisionTimeline.expandedWidth) / 2)
            .contentShape(Rectangle())
            .onTapGesture {}
        }
    }

    private var timelineCurrentTime: Binding<Double> {
        Binding(
            get: {
                Double(progress) * DesignTokens.PrecisionTimeline.previewDuration
            },
            set: { newValue in
                let duration = DesignTokens.PrecisionTimeline.previewDuration
                guard duration > 0 else {
                    progress = 0
                    return
                }
                let clampedTime = min(max(newValue, 0), duration)
                progress = CGFloat(clampedTime / duration)
            }
        )
    }
}

private struct PrecisionTimelineView: View {
    @Binding var currentTime: Double
    @Binding var pixelsPerSecond: CGFloat

    let duration: Double
    let framesPerSecond: Double

    @GestureState private var gestureStartPixelsPerSecond: CGFloat?
    @State private var isDraggingTimeline = false
    @State private var dragStartTime: Double = 0

    var body: some View {
        let shape = DesignTokens.ShapeToken.card

        VStack(spacing: DesignTokens.Spacing.xxs) {
            header
            rulerAndFilmStrip
        }
        .padding(.horizontal, DesignTokens.PrecisionTimeline.panelPadding)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackgroundEffect(in: shape)
        .contentShape(shape)
        .gesture(zoomGesture)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline")
        .accessibilityLabel("Precision timeline")
    }

    private var header: some View {
        ZStack {
            HStack(spacing: DesignTokens.Spacing.xs) {
                frameStepButton(
                    systemName: "backward.frame",
                    label: "Previous Frame",
                    action: stepBackwardOneFrame
                )

                Text(PrecisionTimelineFormatter.timecode(currentTime, framesPerSecond: framesPerSecond))
                    .font(DesignTokens.Typography.headline)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.PrecisionTimeline.timecodeColor)

                frameStepButton(
                    systemName: "forward.frame",
                    label: "Next Frame",
                    action: stepForwardOneFrame
                )
            }
            .accessibilityIdentifier("DesignPreview-PrecisionTimeline-timecode")

            HStack(spacing: DesignTokens.Spacing.xs) {
                Spacer()
                zoomButton(systemName: "minus", label: "Zoom Out") {
                    adjustZoom(dividing: true)
                }
                zoomRail
                zoomButton(systemName: "plus", label: "Zoom In") {
                    adjustZoom(dividing: false)
                }
            }
        }
        .frame(height: DesignTokens.PrecisionTimeline.frameButtonHitSize)
    }

    private var zoomRail: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let progress = normalizedZoom
            let thumbX = width * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)
                    .frame(height: DesignTokens.PrecisionTimeline.zoomRailHeight)
                    .glassBackgroundEffect(in: Capsule())

                Capsule()
                    .fill(DesignTokens.PrecisionTimeline.zoomRailFill)
                    .frame(height: DesignTokens.PrecisionTimeline.zoomRailHeight)

                Capsule()
                    .fill(DesignTokens.PrecisionTimeline.zoomRailActiveFill)
                    .frame(width: max(DesignTokens.PrecisionTimeline.zoomRailHeight, thumbX),
                           height: DesignTokens.PrecisionTimeline.zoomRailHeight)

                Circle()
                    .fill(DesignTokens.PrecisionTimeline.timecodeColor)
                    .frame(width: DesignTokens.PrecisionTimeline.zoomRailThumbSize,
                           height: DesignTokens.PrecisionTimeline.zoomRailThumbSize)
                    .position(x: thumbX, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(zoomRailGesture(width: width))
        }
        .frame(width: DesignTokens.PrecisionTimeline.zoomRailWidth,
               height: DesignTokens.PrecisionTimeline.zoomButtonSize)
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-zoom-rail")
        .accessibilityLabel("Timeline zoom")
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
            .contentShape(.hoverEffect, shape)
            .hoverEffect(.automatic)
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

    private func frameStepButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.SymbolSize.control)
                .foregroundStyle(DesignTokens.PrecisionTimeline.timecodeColor)
                .frame(
                    width: DesignTokens.PrecisionTimeline.frameButtonSize,
                    height: DesignTokens.PrecisionTimeline.frameButtonSize
                )
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle(), displayMode: .implicit)
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.lift)
        }
        .buttonStyle(.plain)
        .frame(
            width: DesignTokens.PrecisionTimeline.frameButtonHitSize,
            height: DesignTokens.PrecisionTimeline.frameButtonHitSize
        )
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-button-\(label)")
        .accessibilityLabel(label)
    }

    private func zoomButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(DesignTokens.PrecisionTimeline.secondaryTextColor)
                .frame(
                    width: DesignTokens.PrecisionTimeline.zoomButtonSize,
                    height: DesignTokens.PrecisionTimeline.zoomButtonSize
                )
                .clipShape(Circle())
                .glassBackgroundEffect(in: Circle(), displayMode: .implicit)
                .contentShape(.hoverEffect, Circle())
                .hoverEffect(.lift)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PrecisionTimeline-button-\(label)")
        .accessibilityLabel(label)
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
                }

                let delta = Double(value.translation.width / pixelsPerSecond)
                let targetTime = dragStartTime - delta
                currentTime = quantizedIfNeeded(clampedTime(targetTime))
            }
            .onEnded { _ in
                isDraggingTimeline = false
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
        let visibleStart = max(-leadingX, 0)
        let visibleEnd = min(viewportWidth - leadingX, contentWidth)
        guard visibleStart <= visibleEnd else { return }

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

        let segmentWidth = max(
            DesignTokens.PrecisionTimeline.thumbnailMinWidth,
            pixelsPerSecond * DesignTokens.PrecisionTimeline.thumbnailSecondsScale
        )
        let startIndex = max(Int(floor(-leadingX / segmentWidth)), 0)
        let endIndex = min(
            Int(ceil((viewportWidth - leadingX) / segmentWidth)),
            Int(ceil(CGFloat(duration) * pixelsPerSecond / segmentWidth))
        )
        guard startIndex <= endIndex else { return }

        for index in startIndex...endIndex {
            let x = leadingX + CGFloat(index) * segmentWidth
            let rect = CGRect(
                x: x,
                y: DesignTokens.PrecisionTimeline.filmImageInset,
                width: segmentWidth,
                height: max(size.height - DesignTokens.PrecisionTimeline.filmImageInset * 2, 1)
            )
            let palette = DesignTokens.PrecisionTimeline.thumbnailPalette
            let color = palette[index % palette.count]
            let path = Path(rect.insetBy(dx: DesignTokens.Stroke.regular, dy: DesignTokens.Stroke.subtle))

            context.fill(path, with: .color(color))
            context.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.minY + DesignTokens.Stroke.regular,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.34
                )),
                with: .color(DesignTokens.PrecisionTimeline.filmStripHighlight)
            )
            context.fill(
                Path(CGRect(
                    x: rect.minX + DesignTokens.Stroke.regular,
                    y: rect.midY,
                    width: max(rect.width - DesignTokens.Stroke.bold, 0),
                    height: rect.height * 0.5
                )),
                with: .color(Color.black.opacity(0.12))
            )
            context.fill(
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

        let startIndex = Int(floor(visibleStart / step))
        let endIndex = Int(ceil(visibleEnd / step))
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

    private func adjustZoom(dividing: Bool) {
        let ratio = DesignTokens.PrecisionTimeline.zoomStepRatio
        let next = dividing ? pixelsPerSecond / ratio : pixelsPerSecond * ratio
        withAnimation(DesignTokens.AnimationToken.selection) {
            pixelsPerSecond = clampedPixelsPerSecond(next)
        }
    }

    private var normalizedZoom: CGFloat {
        let minValue = log(Double(DesignTokens.PrecisionTimeline.minPixelsPerSecond))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let current = log(Double(clampedPixelsPerSecond(pixelsPerSecond)))
        guard maxValue > minValue else { return 0 }
        return CGFloat(min(max((current - minValue) / (maxValue - minValue), 0), 1))
    }

    private func zoomRailGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let normalized = min(max(value.location.x / max(width, 1), 0), 1)
                pixelsPerSecond = zoomValue(forNormalized: normalized)
            }
    }

    private func zoomValue(forNormalized normalized: CGFloat) -> CGFloat {
        let minValue = log(Double(DesignTokens.PrecisionTimeline.minPixelsPerSecond))
        let maxValue = log(Double(DesignTokens.PrecisionTimeline.maxPixelsPerSecond))
        let value = minValue + (maxValue - minValue) * Double(normalized)
        return clampedPixelsPerSecond(CGFloat(exp(value)))
    }

    private func stepBackwardOneFrame() {
        currentTime = clampedTime(currentTime - frameDuration)
    }

    private func stepForwardOneFrame() {
        currentTime = clampedTime(currentTime + frameDuration)
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

struct PlayerProgressStrip: View {
    var timelineResetToken = 0

    var body: some View {
        PlayerProgressBar(timelineResetToken: timelineResetToken)
        .accessibilityIdentifier("DesignPreview-PlayerProgressStrip")
        .accessibilityLabel("Playback progress")
    }
}

struct PlayerControlBar: View {
    var body: some View {
        controlRow
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.ControlBar.paddingH)
        .padding(.vertical, DesignTokens.ControlBar.paddingV)
        .clipShape(Capsule())
        .glassBackgroundEffect(in: .capsule)
        .contentShape(Capsule())
    }

    private var controlRow: some View {
        HStack(spacing: DesignTokens.ControlBar.buttonSpacing) {
            controlButton("gobackward.10", label: "Rewind 10 seconds")
            primaryPlayButton
            controlButton("goforward.10", label: "Forward 10 seconds")
            moreMenu
        }
    }

    private var primaryPlayButton: some View {
        Button {} label: {
            Image(systemName: "play.fill")
                .font(DesignTokens.SymbolSize.action)
                .foregroundStyle(.white)
                .frame(width: DesignTokens.Interactive.xl,
                       height: DesignTokens.Interactive.xl)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .enchronPressFeedback(.icon)
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PlayerControlBar-button-play")
        .accessibilityLabel("Play")
    }

    private var moreMenu: some View {
        Menu {
            Section("Playback Settings") {
                Menu("Subtitles") {
                    menuOption("Off")
                    menuOption("English CC")
                    menuOption("中文简体")
                    menuOption("Auto")
                }

                Menu("Audio Track") {
                    menuOption("English 5.1")
                    menuOption("Japanese 2.0")
                    menuOption("Commentary")
                }

                Menu("Playback Speed") {
                    menuOption("0.5x")
                    menuOption("1x")
                    menuOption("1.25x")
                    menuOption("1.5x")
                    menuOption("2x")
                }

                Menu("Episodes") {
                    menuOption("Episode 1 · The Signal")
                    menuOption("Episode 2 · Night Crossing")
                    menuOption("Episode 3 · Glass Harbor")
                    menuOption("Episode 4 · Quiet Orbit")
                    menuOption("Episode 5 · Afterimage")
                    menuOption("Episode 6 · The Long Return")
                }
            }
        } label: {
            controlIcon("ellipsis")
        }
        .buttonStyle(.plain)
        .enchronPressFeedback(.icon)
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PlayerControlBar-menu-more")
        .accessibilityLabel("More playback settings")
    }

    private func controlButton(_ systemName: String, label: String) -> some View {
        Button {} label: {
            controlIcon(systemName)
        }
        .buttonStyle(.plain)
        .enchronPressFeedback(.icon)
        .contentShape(.hoverEffect, Circle())
        .hoverEffect(.lift)
        .contentShape(Circle())
        .accessibilityIdentifier("DesignPreview-PlayerControlBar-button-\(label)")
        .accessibilityLabel(label)
    }

    private func controlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(DesignTokens.SymbolSize.control)
            .frame(width: DesignTokens.Interactive.large,
                   height: DesignTokens.Interactive.large)
    }

    private func menuOption(_ title: String) -> some View {
        Button {} label: {
            Text(title)
        }
    }

}

// MARK: - Loading spinner

/// Arc shape with independently animatable start/end values.
private struct SpinnerArc: Shape {
    var start: CGFloat
    var end: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(start, end) }
        set { start = newValue.first; end = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
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
