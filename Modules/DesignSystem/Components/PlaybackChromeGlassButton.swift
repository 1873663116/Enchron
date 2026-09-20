import SwiftUI

/// A circular icon control whose surface is platform glass rather than a
/// material. It exists for the playback window's top chrome, which floats over
/// video instead of resting on the window's own surface.
public struct PlaybackChromeGlassButton: View {
    private let systemName: String
    private let accessibilityLabel: String
    private let action: () -> Void
    private let accessibilityIdentifier: String
    private var iconTier: ButtonIconTier = .standard
    private var isEnabled = true

    public init(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        accessibilityIdentifier: String,
        iconTier: ButtonIconTier = .standard
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.iconTier = iconTier
    }

    public func disabled(_ isDisabled: Bool) -> PlaybackChromeGlassButton {
        var copy = self
        copy.isEnabled = !isDisabled
        return copy
    }

    public var body: some View {
        Button(action: action) {
            PlaybackChromeGlassIcon(
                systemName: systemName,
                accessibilityLabel: accessibilityLabel,
                iconTier: iconTier
            )
            .accessibilityHidden(true)
            .frame(
                width: DesignTokens.Interactive.large,
                height: DesignTokens.Interactive.large
            )
            .contentShape(Circle())
        }
        .buttonStyle(EnchronPressFeedbackButtonStyle(.icon))
        .disabled(!isEnabled)
        .playbackChromeGlassHitArea()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// The same control with a `Menu` for its action, for the top chrome's overflow.
public struct PlaybackChromeGlassMenuButton<Content: View>: View {
    private let systemName: String
    private let accessibilityLabel: String
    private let accessibilityIdentifier: String
    private var iconTier: ButtonIconTier = .standard
    private var onOpen: (@MainActor () -> Void)?
    @ViewBuilder private var content: () -> Content

    public init(
        systemName: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        iconTier: ButtonIconTier = .standard,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.iconTier = iconTier
        self.content = content
    }

    public func onOpen(_ action: @escaping @MainActor () -> Void) -> PlaybackChromeGlassMenuButton {
        var copy = self
        copy.onOpen = action
        return copy
    }

    public var body: some View {
        Menu {
            content()
                .onAppear { onOpen?() }
        } label: {
            PlaybackChromeGlassIcon(
                systemName: systemName,
                accessibilityLabel: accessibilityLabel,
                iconTier: iconTier
            )
            .accessibilityHidden(true)
            .frame(
                width: DesignTokens.Interactive.large,
                height: DesignTokens.Interactive.large
            )
            .contentShape(Circle())
        }
        .simultaneousGesture(TapGesture().onEnded { onOpen?() })
        .buttonStyle(EnchronPressFeedbackButtonStyle.menuIcon())
        .playbackChromeGlassHitArea()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct PlaybackChromeGlassIcon: View {
    let systemName: String
    let accessibilityLabel: String
    let iconTier: ButtonIconTier

    var body: some View {
        ButtonSymbol(systemName: systemName, tier: iconTier)
            .foregroundStyle(.white)
            .frame(
                width: DesignTokens.Interactive.regular,
                height: DesignTokens.Interactive.regular
            )
            .clipShape(Circle())
            .enchronGlassBackground(in: Circle())
            .enchronHoverContentShape(Circle())
            .enchronHoverEffect(.highlight)
            .enchronSpatialOffset(z: 1)
    }
}

private extension View {
    func playbackChromeGlassHitArea() -> some View {
        contentShape(Circle())
            .contentShape(
                .hoverEffect,
                Circle().inset(
                    by: (DesignTokens.Interactive.large - DesignTokens.Interactive.regular) / 2
                )
            )
    }
}
