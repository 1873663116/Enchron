import SwiftUI

public enum DirectionalIconDirection: Sendable, Equatable {
    case backward
    case forward
}

/// A directional icon button that preserves the supplied SF Symbol and delegates
/// its internal layer animation to the system symbol effect.
public struct AnimatedDirectionalIconButton: View {
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
        if accessibilityReduceMotion {
            staticArtwork
        } else {
            switch direction {
            case .backward:
                staticArtwork
                    .symbolEffect(
                        .rotate.counterClockwise.byLayer,
                        options: .speed(1.15),
                        value: trigger
                    )
            case .forward:
                staticArtwork
                    .symbolEffect(
                        .rotate.clockwise.byLayer,
                        options: .speed(1.15),
                        value: trigger
                    )
            }
        }
    }

    private var staticArtwork: some View {
        Image(systemName: systemName)
            .font(iconTier.font)
            .frame(width: iconTier.artworkSize, height: iconTier.artworkSize)
    }
}
