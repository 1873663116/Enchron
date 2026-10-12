import SwiftUI

public struct ViewModeCapsuleControl: View {
    @Binding var selection: Int
    var accessibilityIdentifier: String = "DesignSystem-control-viewMode"
    var accessibilityLabel: String = "View Mode"

    private let iconColor: Color = .white
    private let unselectedOpacity = DesignTokens.Interactive.viewModeInactiveOpacity

    @Namespace private var indicatorNamespace
    @State private var pressedIndex: Int?
    @State private var pressFeedbackTrigger = 0

    public var body: some View {
        let capsuleWidth = DesignTokens.Interactive.regular * 2
        ZStack {
            HStack(spacing: 0) {
                Button { select(0) } label: {
                    viewModeIcon("square.grid.2x2", isSelected: selection == 0, isPressed: pressedIndex == 0)
                }
                .accessibilityLabel("Grid view")
                Button { select(1) } label: {
                    viewModeIcon("list.bullet", isSelected: selection == 1, isPressed: pressedIndex == 1)
                }
                .accessibilityLabel("List view")
            }
            .buttonStyle(.plain)
            .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
            .background {
                Capsule()
                    .fill(.clear)
                    .frame(height: DesignTokens.Interactive.regular)
                    .enchronGlassControlSurface()
            }
        }
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .contentShape(Rectangle())
        .enchronPressSensoryFeedback(.iconOnly, trigger: pressFeedbackTrigger)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selection == 0 ? "grid" : "list")
        .accessibilityHint("Tap left half for grid, right half for list")
    }

    private func select(_ index: Int) {
        let press = DesignTokens.PressFeedback.icon
        pressFeedbackTrigger += 1
        withAnimation(press.pressAnimation) { pressedIndex = index }
        Task {
            try? await Task.sleep(for: press.holdDuration)
            withAnimation(DesignTokens.AnimationToken.selection) {
                selection = index
                pressedIndex = nil
            }
        }
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

            ButtonSymbol(systemName: icon)
                .foregroundStyle(isSelected ? iconColor : iconColor.opacity(unselectedOpacity))
                .scaleEffect(isPressed ? press.pressedScale : 1.0)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
        .enchronHoverTarget(
            visual: Circle(),
            interaction: Rectangle(),
            insets: EdgeInsets(top: DesignTokens.Spacing.xs, leading: 0,
                               bottom: DesignTokens.Spacing.xs, trailing: 0)
        )
    }

    public init(
        selection: Binding<Int>,
        accessibilityIdentifier: String = "DesignSystem-control-viewMode",
        accessibilityLabel: String = "View Mode"
    ) {
        self._selection = selection
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
    }
}
