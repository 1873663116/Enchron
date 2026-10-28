import DesignSystem
import SwiftUI

public struct StreamingCapsule<Leading: View, Center: View, Trailing: View, Panel: View>: View {
    private let panelSize: CGSize
    private let accessibilityIdentifierPrefix: String
    private let leading: (Binding<Bool>) -> Leading
    private let center: (Binding<Bool>) -> Center
    private let trailing: (Binding<Bool>) -> Trailing
    private let panel: () -> Panel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isMorphing = false

    public init(
        panelSize: CGSize,
        accessibilityIdentifierPrefix: String,
        @ViewBuilder leading: @escaping (Binding<Bool>) -> Leading,
        @ViewBuilder center: @escaping (Binding<Bool>) -> Center,
        @ViewBuilder trailing: @escaping (Binding<Bool>) -> Trailing,
        @ViewBuilder panel: @escaping () -> Panel
    ) {
        self.panelSize = panelSize
        self.accessibilityIdentifierPrefix = accessibilityIdentifierPrefix
        self.leading = leading
        self.center = center
        self.trailing = trailing
        self.panel = panel
    }

    public var body: some View {
        ZStack {
            panelLayer
            if isExpanded == false {
                ExpandingControls {
                    center(expansion)
                } secondary: {
                    leading(expansion)
                } trailing: {
                    trailing(expansion)
                }
                .transition(capsuleTransition)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifierPrefix)
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { isExpanded },
            set: { setExpanded($0) }
        )
    }

    private var panelLayer: some View {
        panel()
            .frame(width: panelSize.width, height: panelSize.height)
            .overlay(alignment: .topTrailing) {
                CircleIconButton.close(
                    accessibilityLabel: String(localized: "Close"),
                    action: { setExpanded(false) },
                    accessibilityIdentifier: "\(accessibilityIdentifierPrefix)-close"
                )
                .padding(DesignTokens.Spacing.lg)
            }
            .opacity(isExpanded ? 1 : 0)
            .animation(contentAnimation, value: isExpanded)
            .clipShape(revealShape)
            .enchronGlassBackground(in: revealShape, displayMode: plateGlassMode)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(isExpanded == false)
    }

    private var containerSize: CGSize {
        isExpanded ? panelSize : DesignTokens.EnvironmentHome.compactSize
    }

    private var revealShape: CenteredRevealShape {
        guard isExpanded == false else {
            return CenteredRevealShape(size: panelSize, cornerRadius: DesignTokens.Radius.card)
        }
        let restingDiameter = DesignTokens.EnvironmentHome.compactSize.height
        return CenteredRevealShape(
            size: CGSize(width: restingDiameter, height: restingDiameter),
            cornerRadius: restingDiameter / 2
        )
    }

    private var capsuleTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(
                reduceMotion ? nil : DesignTokens.AnimationToken.environmentControlsEntrance
            ),
            removal: .opacity.animation(
                reduceMotion ? nil : DesignTokens.AnimationToken.environmentControlsExit
            )
        )
    }

    private var contentAnimation: Animation? {
        guard reduceMotion == false else { return nil }
        return isExpanded
            ? DesignTokens.AnimationToken.environmentContentEntrance
            : DesignTokens.AnimationToken.environmentContentExit
    }

    private var plateGlassMode: GlassBackgroundDisplayMode {
        isExpanded || isMorphing ? .always : .never
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isMorphing = true
        withAnimation(
            reduceMotion ? nil : DesignTokens.AnimationToken.environmentPlateMorph,
            completionCriteria: .removed
        ) {
            isExpanded = expanded
        } completion: {
            isMorphing = false
        }
    }
}

public struct StreamingCapsuleSlotButton<Icon: View>: View {
    @Environment(\.isEnabled) private var isEnabled

    private let accessibilityLabel: String
    private let accessibilityIdentifier: String
    private let action: () -> Void
    private let icon: Icon

    public init(
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
        self.icon = icon()
    }

    public var body: some View {
        Button(action: action) {
            icon
                .frame(
                    width: DesignTokens.ButtonIcon.standardArtwork,
                    height: DesignTokens.ButtonIcon.standardArtwork
                )
                .foregroundStyle(.white)
                .frame(
                    width: DesignTokens.EnvironmentHome.buttonSize,
                    height: DesignTokens.EnvironmentHome.buttonSize
                )
                .enchronButtonSurface(in: Circle())
                .enchronHoverContentShape(Circle())
                .enchronHoverEffect(.automatic)
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : DesignTokens.EnvironmentHome.disabledOpacity)
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
