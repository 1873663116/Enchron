import SwiftUI

public enum EnchronPressSensoryFeedback {
    case button
    case iconOnly
    case slider
    case selectionMinimum
    case selectionMaximum
    case selectionOn
}

public extension View {
    @ViewBuilder
    func enchronPressSensoryFeedback<T: Equatable>(
        _ feedback: EnchronPressSensoryFeedback,
        trigger: T
    ) -> some View {
        #if os(visionOS)
        switch feedback {
        case .button:
            sensoryFeedback(.press(.button), trigger: trigger)
        case .iconOnly:
            sensoryFeedback(.press(.buttonIconOnly), trigger: trigger)
        case .slider:
            sensoryFeedback(.press(.slider), trigger: trigger)
        case .selectionMinimum:
            sensoryFeedback(.selection(.minimum), trigger: trigger)
        case .selectionMaximum:
            sensoryFeedback(.selection(.maximum), trigger: trigger)
        case .selectionOn:
            sensoryFeedback(.selection(.on), trigger: trigger)
        }
        #else
        self
        #endif
    }
}

public enum EnchronPressFeedbackStyle {
    case card
    case row
    case control
    case icon

    var spec: DesignTokens.PressFeedbackSpec {
        switch self {
        case .card:
            DesignTokens.PressFeedback.card
        case .row:
            DesignTokens.PressFeedback.row
        case .control:
            DesignTokens.PressFeedback.control
        case .icon:
            DesignTokens.PressFeedback.icon
        }
    }
}

public struct EnchronPressFeedbackButtonStyle: ButtonStyle {
    let style: EnchronPressFeedbackStyle

    public init(_ style: EnchronPressFeedbackStyle) {
        self.style = style
    }

    public func makeBody(configuration: Configuration) -> some View {
        EnchronPressFeedbackButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            style: style
        )
    }
}

private struct EnchronPressFeedbackButtonStyleBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let style: EnchronPressFeedbackStyle

    @State private var measuredSize: CGSize = .zero

    var body: some View {
        let spec = style.spec

        label
            .scaleEffect(isPressed ? spec.effectivePressedScale(for: measuredSize) : 1.0)
            .animation(
                isPressed ? spec.pressAnimation : spec.releaseAnimation,
                value: isPressed
            )
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            measuredSize = newSize
                        }
                }
            }
    }
}
