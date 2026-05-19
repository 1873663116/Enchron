import SwiftUI

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

private struct EnchronPressFeedbackModifier: ViewModifier {
    let style: EnchronPressFeedbackStyle
    @State private var isPressed = false
    @State private var measuredSize: CGSize = .zero

    func body(content: Content) -> some View {
        let spec = style.spec

        content
            .scaleEffect(isPressed ? spec.effectivePressedScale(for: measuredSize) : 1.0)
            .animation(spec.pressAnimation, value: isPressed)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredSize = proxy.size }
                        .onChange(of: proxy.size) { _, newSize in
                            measuredSize = newSize
                        }
                }
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    withAnimation(spec.pressAnimation) {
                        isPressed = true
                    }

                    Task {
                        try? await Task.sleep(for: spec.holdDuration)
                        withAnimation(spec.releaseAnimation) {
                            isPressed = false
                        }
                    }
                }
            )
    }
}
public extension View {
    func enchronPressFeedback(_ style: EnchronPressFeedbackStyle) -> some View {
        modifier(EnchronPressFeedbackModifier(style: style))
    }
}
