import DesignSystem
import MediaLibrary
import SwiftUI

public struct NavBackForwardCapsuleControl: View {
    let canGoBack: Bool
    let canGoForward: Bool
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var accessibilityIdentifier: String = "DesignSystem-control-navBackForward"

    private let iconColor: Color = .white
    private let disabledOpacity: Double = 0.45

    public var body: some View {
        let capsuleWidth = DesignTokens.Interactive.regular * 2

        HStack(spacing: 0) {
            Button(action: onBack) {
                ButtonSymbol(systemName: "chevron.left")
                    .foregroundStyle(
                        iconColor.opacity(canGoBack ? 1 : disabledOpacity)
                    )
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                    .contentShape(Rectangle())
            }
            .buttonStyle(
                EnchronPressFeedbackButtonStyle(
                    .icon,
                    playsSensoryFeedback: true
                )
            )
            .disabled(!canGoBack)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("\(accessibilityIdentifier)-back")

            Button(action: onForward) {
                ButtonSymbol(systemName: "chevron.right")
                    .foregroundStyle(
                        iconColor.opacity(canGoForward ? 1 : disabledOpacity)
                    )
                    .frame(width: DesignTokens.Interactive.regular,
                           height: DesignTokens.Interactive.regular)
                    .contentShape(Rectangle())
            }
            .buttonStyle(
                EnchronPressFeedbackButtonStyle(
                    .icon,
                    playsSensoryFeedback: true
                )
            )
            .disabled(!canGoForward)
            .accessibilityLabel("Forward")
            .accessibilityIdentifier("\(accessibilityIdentifier)-forward")
        }
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.regular)
        .enchronGlassControl()
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    public init(
        canGoBack: Bool,
        canGoForward: Bool,
        onBack: @escaping () -> Void = {},
        onForward: @escaping () -> Void = {},
        accessibilityIdentifier: String = "DesignSystem-control-navBackForward"
    ) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.onBack = onBack
        self.onForward = onForward
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

public struct ViewModeCapsuleControl: View {
    @Binding var selection: Int
    var accessibilityIdentifier: String = "DesignSystem-control-viewMode"
    var accessibilityLabel: String = "View Mode"

    private let iconColor: Color = .white
    private let unselectedOpacity: Double = 0.45

    @Namespace private var indicatorNamespace
    @State private var pressedIndex: Int?
    @State private var pressFeedbackTrigger = 0

    public var body: some View {
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
        .enchronPressSensoryFeedback(.iconOnly, trigger: pressFeedbackTrigger)
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

            ButtonSymbol(systemName: icon)
                .foregroundStyle(isSelected ? iconColor : iconColor.opacity(unselectedOpacity))
                .scaleEffect(isPressed ? press.pressedScale : 1.0)
                .frame(width: DesignTokens.Interactive.regular,
                       height: DesignTokens.Interactive.regular)
        }
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
