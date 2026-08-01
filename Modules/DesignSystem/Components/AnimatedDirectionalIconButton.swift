import SwiftUI

public enum DirectionalIconDirection: Sendable, Equatable {
    case backward
    case forward

    fileprivate var revealAlignment: Alignment {
        switch self {
        case .backward: .trailing
        case .forward: .leading
        }
    }

    fileprivate var settleRotation: Double {
        switch self {
        case .backward: -9
        case .forward: 9
        }
    }
}

/// A directional icon button whose artwork reveals from its tail and settles with
/// a small directional rotation. The fixed artwork frame keeps the motion inside
/// the button instead of translating the control itself.
public struct AnimatedDirectionalIconButton: View {
    private struct AnimationValues {
        var reveal: CGFloat = 1
        var opacity: CGFloat = 1
        var rotation: Double = 0
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
        let revealAlignment = direction.revealAlignment
        let settleRotation = direction.settleRotation

        if accessibilityReduceMotion {
            staticArtwork
        } else {
            staticArtwork
                .keyframeAnimator(
                    initialValue: AnimationValues(),
                    trigger: trigger
                ) { content, value in
                    content
                        .opacity(value.opacity)
                        .rotationEffect(.degrees(value.rotation))
                        .mask {
                            GeometryReader { proxy in
                                Rectangle()
                                    .frame(width: proxy.size.width * value.reveal)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: revealAlignment
                                    )
                            }
                        }
                } keyframes: { _ in
                    KeyframeTrack(\.reveal) {
                        LinearKeyframe(0.08, duration: 0.02)
                        CubicKeyframe(0.52, duration: 0.08)
                        CubicKeyframe(1, duration: 0.15)
                    }
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0.18, duration: 0.02)
                        CubicKeyframe(1, duration: 0.16)
                    }
                    KeyframeTrack(\.rotation) {
                        CubicKeyframe(settleRotation, duration: 0.16)
                        CubicKeyframe(settleRotation * -0.22, duration: 0.06)
                        CubicKeyframe(0, duration: 0.07)
                    }
                }
        }
    }

    private var staticArtwork: some View {
        Image(systemName: systemName)
            .font(iconTier.font)
            .frame(width: iconTier.artworkSize, height: iconTier.artworkSize)
    }

}
