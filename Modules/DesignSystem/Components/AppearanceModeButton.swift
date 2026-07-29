import SwiftUI

public struct AppearanceModeButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let isActive: Bool
    let accessibilityLabel: String
    var action: () -> Void
    var accessibilityIdentifier: String?
    var visualSize: CGFloat
    var targetSize: CGFloat

    public init(
        isActive: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void = {},
        accessibilityIdentifier: String? = nil,
        visualSize: CGFloat = DesignTokens.Interactive.regular,
        targetSize: CGFloat = DesignTokens.Interactive.large
    ) {
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.visualSize = visualSize
        self.targetSize = targetSize
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white)
                    .opacity(isActive ? 1 : 0)

                AppearanceModeGlyph(isActive: isActive)
                    .frame(
                        width: DesignTokens.ButtonIcon.standardArtwork,
                        height: DesignTokens.ButtonIcon.standardArtwork
                    )
                    .rotationEffect(.degrees(isActive ? 180 : 0))
            }
            .animation(DesignTokens.AnimationToken.selection, value: isActive)
            .frame(width: visualSize, height: visualSize)
            .enchronGlassBackground(in: Circle())
            .enchronHoverContentShape(Circle())
            .enchronHoverEffect(.automatic)
            .frame(width: targetSize, height: targetSize)
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isActive ? "Active" : "Inactive")
        .accessibilityIdentifier(
            accessibilityIdentifier ?? "DesignPreview-button-appearanceMode"
        )
    }

    private enum Metrics {
        static let disabledOpacity = 0.32
    }
}

private struct AppearanceModeGlyph: View {
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let color = isActive ? Color.black : Color.white

            ZStack {
                Circle()
                    .strokeBorder(
                        color,
                        lineWidth: size * Metrics.outerStrokeRatio
                    )

                Circle()
                    .strokeBorder(
                        color,
                        lineWidth: size * Metrics.middleRingWidthRatio
                    )
                    .mask(alignment: .trailing) {
                        Rectangle()
                            .frame(width: size / 2, height: size)
                    }

                Circle()
                    .fill(color)
                    .frame(
                        width: size * Metrics.centerDiameterRatio,
                        height: size * Metrics.centerDiameterRatio
                    )
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(
                                width: size * Metrics.centerDiameterRatio / 2,
                                height: size * Metrics.centerDiameterRatio
                            )
                    }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private enum Metrics {
        static let outerStrokeRatio: CGFloat = 0.08
        static let middleRingWidthRatio: CGFloat = 0.32
        static let centerDiameterRatio: CGFloat = 0.36
    }
}
