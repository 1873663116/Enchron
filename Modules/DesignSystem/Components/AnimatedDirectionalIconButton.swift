import SwiftUI

public enum DirectionalIconDirection: Sendable, Equatable {
    case backward
    case forward

    fileprivate var actionRotation: Double {
        switch self {
        case .backward: -22
        case .forward: 22
        }
    }

    fileprivate var arrowSystemName: String {
        switch self {
        case .backward: "gobackward"
        case .forward: "goforward"
        }
    }
}

/// A directional icon button whose artwork reveals from its tail and settles with
/// a small directional rotation. The fixed artwork frame keeps the motion inside
/// the button instead of translating the control itself.
public struct AnimatedDirectionalIconButton: View {
    private struct AnimationValues {
        var rotation: Double = 0
        var scale: CGFloat = 1
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private let systemName: String
    private let direction: DirectionalIconDirection
    private let trigger: Int
    private let accessibilityLabel: String
    private let action: () -> Void
    private let accessibilityIdentifier: String?
    private let visualSize: CGFloat
    private let targetSize: CGFloat
    private let iconTier: ButtonIconTier

    public init(
        systemName: String,
        direction: DirectionalIconDirection,
        trigger: Int,
        accessibilityLabel: String,
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        targetSize: CGFloat = DesignTokens.Interactive.large,
        iconTier: ButtonIconTier = .standard
    ) {
        self.systemName = systemName
        self.direction = direction
        self.trigger = trigger
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.visualSize = visualSize
        self.targetSize = targetSize
        self.iconTier = iconTier
    }

    public var body: some View {
        Button(action: action) {
            artwork
                .foregroundStyle(.white)
                .frame(width: visualSize, height: visualSize)
                .clipShape(Circle())
                .enchronGlassBackground(in: Circle())
                .enchronHoverContentShape(Circle())
                .enchronHoverEffect(.automatic)
                .opacity(isEnabled ? 1 : 0.32)
                .frame(width: targetSize, height: targetSize)
                .contentShape(Circle())
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier ?? "DesignSystem-animated-directional-icon")
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            animatedArrow
            Text("15")
                .font(.system(size: numberSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: iconTier.artworkSize, height: iconTier.artworkSize)
    }

    @ViewBuilder
    private var animatedArrow: some View {
        if accessibilityReduceMotion {
            arrowArtwork
        } else {
            arrowArtwork
                .keyframeAnimator(
                    initialValue: AnimationValues(),
                    trigger: trigger
                ) { content, value in
                    content
                        .rotationEffect(.degrees(value.rotation))
                        .scaleEffect(value.scale)
                } keyframes: { _ in
                    KeyframeTrack(\.rotation) {
                        CubicKeyframe(direction.actionRotation, duration: 0.11)
                        CubicKeyframe(direction.actionRotation * -0.12, duration: 0.08)
                        CubicKeyframe(0, duration: 0.09)
                    }
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(0.92, duration: 0.1)
                        CubicKeyframe(1, duration: 0.18)
                    }
                }
        }
    }

    private var arrowArtwork: some View {
        Image(systemName: direction.arrowSystemName)
            .font(iconTier.font)
            .frame(width: iconTier.artworkSize, height: iconTier.artworkSize)
    }

    private var numberSize: CGFloat {
        max(7, iconTier.artworkSize * 0.3)
    }

}
