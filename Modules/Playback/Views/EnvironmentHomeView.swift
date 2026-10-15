import DesignSystem
import SwiftUI

public struct EnvironmentHomeView: View {
    @Environment(PlaybackSessionModel.self) private var appModel
    @Binding private var isCompact: Bool

    public init(isCompact: Binding<Bool>) {
        _isCompact = isCompact
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(
                    systemName: "minus",
                    accessibilityLabel: String(localized: "Minimize environments"),
                    action: { isCompact = true },
                    accessibilityIdentifier: "EnvironmentHome-button-minimize"
                )
                Spacer()
                Text("Environments")
                    .font(.title2.weight(.semibold))
                Spacer()
                Color.clear
                    .frame(width: DesignTokens.Interactive.large, height: DesignTokens.Interactive.large)
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .frame(height: DesignTokens.EnvironmentHome.headerHeight)
            Spacer(minLength: 0)
            EnvironmentCardCarousel(
                activeEnvironment: appModel.environmentContext.environment,
                cardDefaultEnvironment: appModel.defaultCardEnvironment,
                isPresented: true,
                onSetDefault: appModel.setDefaultCardEnvironment,
                defaultEffect: appModel.currentEnvironmentEffect,
                onEffectChange: updateEnvironmentEffect,
                onExpand: toggleEnvironment
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("EnvironmentHome-page")
        .accessibilityLabel("Environments")
        .onAppear { appModel.receiveSpatialPlatformResult(.environmentCardAppeared) }
        .onDisappear { appModel.receiveSpatialPlatformResult(.environmentCardDisappeared) }
    }

    private func updateEnvironmentEffect(
        _ featured: FeaturedEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentCard effect delivered environment=\(featured.environment.rawValue)"
                + " effect=\(effect.rawValue)",
            retention: .evidence
        )
#endif
        guard appModel.environmentContext.environment == featured.environment else {
            return
        }
        appModel.setActiveEnvironmentEffect(effect)
    }

    private func toggleEnvironment(
        _ featured: FeaturedEnvironment,
        effect: SpatialSceneDomain.EnvironmentEffect
    ) {
        do {
#if DEBUG
            appModel.recordSurfaceInputProbe(
                "environmentCard toggle delivered environment=\(featured.environment.rawValue)"
                    + " effect=\(effect.rawValue)",
                retention: .evidence
            )
#endif
            try appModel.toggleEnvironmentPreview(environment: featured.environment, effect: effect)
        } catch {
            return
        }
    }
}

public struct EnvironmentMiniControls: View {
    @Environment(PlaybackSessionModel.self) private var appModel
    private let restore: () -> Void

    public init(restore: @escaping () -> Void) {
        self.restore = restore
    }

    public var body: some View {
        ExpandingControls {
            EnvironmentMiniButton(
                accessibilityLabel: String(localized: "Restore environments"),
                accessibilityIdentifier: "EnvironmentHome-button-restore",
                action: restore
            ) {
                WindowRestoreIcon()
            }
        } secondary: {
            EnvironmentMiniButton(
                accessibilityLabel: appModel.currentEnvironmentEffect == .dark ? String(localized: "Light Mode") : String(localized: "Dark Mode"),
                accessibilityIdentifier: "EnvironmentHome-button-appearance",
                action: {
                    appModel.setActiveEnvironmentEffect(appModel.currentEnvironmentEffect == .dark ? .light : .dark)
                },
                icon: { AppearanceModeGlyph(isActive: false) }
            )
            .disabled(appModel.immersiveSpaceResidency != .open || appModel.environmentContext.environment?.supportsDarkAppearance != true)
            .accessibilityValue(appModel.currentEnvironmentEffect == .dark ? "Active" : "Inactive")
        } trailing: {
            EnvironmentMiniButton(
                accessibilityLabel: appModel.environmentContext.environment == nil ? String(localized: "Open environment") : String(localized: "Close environment"),
                accessibilityIdentifier: "EnvironmentHome-button-scene",
                action: toggleScene
            ) {
                Image(systemName: CircleIconButton.expansionSymbol(isExpanded: appModel.environmentContext.environment != nil))
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(appModel.pendingSpatialPlatformEffect != nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("EnvironmentHome-compact")
    }

    private func toggleScene() {
        do {
            try appModel.toggleLastEnvironmentPreview()
        } catch {
            return
        }
    }
}

private struct EnvironmentMiniButton<Icon: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: DesignTokens.ButtonIcon.standardArtwork, height: DesignTokens.ButtonIcon.standardArtwork)
                .foregroundStyle(.white)
                .frame(width: DesignTokens.EnvironmentHome.buttonSize, height: DesignTokens.EnvironmentHome.buttonSize)
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
