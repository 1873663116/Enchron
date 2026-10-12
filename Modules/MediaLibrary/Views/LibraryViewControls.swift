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
                    .enchronHoverTarget(
                        visual: Circle(), interaction: Rectangle(),
                        insets: EdgeInsets(top: DesignTokens.Spacing.xs, leading: 0,
                                           bottom: DesignTokens.Spacing.xs, trailing: 0)
                    )
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
                    .enchronHoverTarget(
                        visual: Circle(), interaction: Rectangle(),
                        insets: EdgeInsets(top: DesignTokens.Spacing.xs, leading: 0,
                                           bottom: DesignTokens.Spacing.xs, trailing: 0)
                    )
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
        .frame(width: capsuleWidth, height: DesignTokens.Interactive.large)
        .background {
            Capsule().fill(.clear)
                .frame(height: DesignTokens.Interactive.regular)
                .enchronGlassControlSurface()
        }
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
