import DesignSystem
import SwiftUI

public struct EnvironmentHomeView: View {
    @Environment(PlaybackSessionModel.self) private var appModel
    @Binding private var isCompact: Bool
    private let availableWidth: CGFloat

    public init(isCompact: Binding<Bool>, availableWidth: CGFloat) {
        _isCompact = isCompact
        self.availableWidth = availableWidth
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(
                    systemName: "minus",
                    accessibilityLabel: String(localized: "Minimize environments"),
                    action: minimize,
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
                onSetDefault: setDefaultEnvironment,
                effect: appModel.currentEnvironmentEffect,
                controlsEnabled: appModel.isTransitioningPlaybackPresentation == false,
                onCenterChange: { appModel.cardEnvironment = $0 },
                onEffectChange: updateEnvironmentEffect,
                onToggle: toggleEnvironment,
                availableWidth: availableWidth
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

    private func minimize() {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentHome minimize delivered",
            retention: .evidence
        )
#endif
        isCompact = true
    }

    private func setDefaultEnvironment(
        _ environment: SpatialSceneDomain.CinemaEnvironment
    ) {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentCard default delivered environment=\(environment.rawValue)",
            retention: .evidence
        )
#endif
        appModel.setDefaultCardEnvironment(environment)
    }

    private func updateEnvironmentEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentCard effect delivered environment="
                + "\(appModel.centeredCardEnvironment.rawValue)"
                + " effect=\(effect.rawValue)",
            retention: .evidence
        )
#endif
        appModel.setActiveEnvironmentEffect(effect)
    }

    private func toggleEnvironment() {
        do {
#if DEBUG
            appModel.recordSurfaceInputProbe(
                "environmentCard toggle delivered environment="
                    + "\(appModel.environmentContext.environment?.rawValue ?? appModel.centeredCardEnvironment.rawValue)",
                retention: .evidence
            )
#endif
            try appModel.toggleEnvironmentPreview()
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
                action: restoreEnvironment
            ) {
                WindowRestoreIcon()
            }
        } secondary: {
            AppearanceModeButton(
                isActive: appModel.currentEnvironmentEffect == .dark,
                accessibilityLabel: appModel.currentEnvironmentEffect == .dark
                    ? String(localized: "Light Mode")
                    : String(localized: "Dark Mode"),
                action: toggleAppearance,
                accessibilityIdentifier: "EnvironmentHome-button-appearance",
                visualSize: DesignTokens.EnvironmentHome.buttonSize,
                targetSize: DesignTokens.EnvironmentHome.buttonSize
            )
            .disabled(appModel.isTransitioningPlaybackPresentation)
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
            .disabled(appModel.isTransitioningPlaybackPresentation)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("EnvironmentHome-compact")
    }

    private func restoreEnvironment() {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentHome restore delivered",
            retention: .evidence
        )
#endif
        restore()
    }

    private func toggleAppearance() {
        let effect: SpatialSceneDomain.EnvironmentEffect =
            appModel.currentEnvironmentEffect == .dark ? .light : .dark
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentHome appearance delivered effect=\(effect.rawValue)",
            retention: .evidence
        )
#endif
        appModel.setActiveEnvironmentEffect(effect)
    }

    private func toggleScene() {
#if DEBUG
        appModel.recordSurfaceInputProbe(
            "environmentHome scene delivered environment="
                + "\(appModel.environmentContext.environment?.rawValue ?? "none")",
            retention: .evidence
        )
#endif
        do {
            try appModel.toggleEnvironmentPreview()
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
