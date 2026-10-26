import DesignSystem
import SwiftUI

struct StreamingCapsuleDeck: View {
    enum Mode {
        case window
        case docked(DockedPlacementSettings)
    }

    private enum Panel {
        case information
        case placement
    }

    private let mode: Mode
    private let information: StreamingPlaybackInformation?
    private let onInteraction: () -> Void
    private let onExitDock: () -> Void
    private let dockMenuPresented: Binding<Bool>

    @State private var panel = Panel.information

    init(
        mode: Mode,
        information: StreamingPlaybackInformation?,
        dockMenuPresented: Binding<Bool> = .constant(false),
        onInteraction: @escaping () -> Void = {},
        onExitDock: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.information = information
        self.dockMenuPresented = dockMenuPresented
        self.onInteraction = onInteraction
        self.onExitDock = onExitDock
    }

    var body: some View {
        StreamingCapsule(
            panelSize: panelSize,
            accessibilityIdentifierPrefix: "PlayerUI-StreamingCapsule",
            leading: { expansion in leadingSlot(expansion) },
            center: { _ in centerSlot },
            trailing: { expansion in trailingSlot(expansion) },
            panel: { panelContent }
        )
    }

    @ViewBuilder
    private func leadingSlot(_ expansion: Binding<Bool>) -> some View {
        switch mode {
        case .window:
            settingsSlot(isEnabled: false, action: {})
        case .docked:
            settingsSlot(
                isEnabled: true,
                action: {
                    onInteraction()
                    panel = .placement
                    expansion.wrappedValue = true
                }
            )
        }
    }

    @ViewBuilder
    private var centerSlot: some View {
        switch mode {
        case .window:
            dockSlot
        case .docked:
            exitDockSlot
        }
    }

    @ViewBuilder
    private func trailingSlot(_ expansion: Binding<Bool>) -> some View {
        StreamingCapsuleSlotButton(
            accessibilityLabel: String(localized: "Streaming Information"),
            accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-information",
            action: {
                onInteraction()
                panel = .information
                expansion.wrappedValue = true
            },
            icon: { ButtonSymbol(systemName: "info.circle") }
        )
        .disabled(information == nil)
    }

    private func settingsSlot(
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        StreamingCapsuleSlotButton(
            accessibilityLabel: String(localized: "Settings"),
            accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-settings",
            action: action,
            icon: { ButtonSymbol(systemName: "gear") }
        )
        .disabled(isEnabled == false)
    }

    private var dockSlot: some View {
        StreamingCapsuleSlotButton(
            accessibilityLabel: String(localized: "Dock"),
            accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-dock",
            action: {
                onInteraction()
                dockMenuPresented.wrappedValue.toggle()
            },
            icon: { ButtonSymbol(systemName: "mountain.2.fill") }
        )
    }

    private var exitDockSlot: some View {
        StreamingCapsuleSlotButton(
            accessibilityLabel: String(localized: "Return to Window"),
            accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-exit-dock",
            action: {
                onInteraction()
                onExitDock()
            },
            icon: {
                ButtonSymbol(systemName: "arrow.down.forward.and.arrow.up.backward")
            }
        )
    }

    @ViewBuilder
    private var panelContent: some View {
        switch mode {
        case .window:
            informationPanel
        case .docked(let settings):
            switch panel {
            case .information:
                informationPanel
            case .placement:
                StreamingCapsuleDockedPlacementPanel(settings: settings)
            }
        }
    }

    @ViewBuilder
    private var informationPanel: some View {
        if let information {
            StreamingCapsuleInformationPanel(information: information)
        }
    }

    private var panelSize: CGSize {
        switch mode {
        case .window:
            streamingInformationPanelSize
        case .docked:
            panel == .placement
                ? dockedPlacementPanelSize
                : streamingInformationPanelSize
        }
    }

    private var streamingInformationPanelSize: CGSize {
        CGSize(
            width: DesignTokens.ControlBar.contentWidth,
            height: DesignTokens.Layout.playbackMediaInfoHeight * 2
        )
    }

    private var dockedPlacementPanelSize: CGSize {
        CGSize(
            width: DesignTokens.ControlBar.contentWidth,
            height: DesignTokens.Layout.playbackMediaInfoHeight * 4
        )
    }
}

struct StreamingCapsuleDockedPlacementPanel: View {
    let settings: DockedPlacementSettings

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Spacer(minLength: 0)
                DockedPlacementResetAction(settings: settings)
            }
            .padding(.trailing, DesignTokens.Interactive.large)

            DockedPlacementSliders(
                settings: settings,
                contentWidth: DesignTokens.ControlBar.contentWidth
                    - DesignTokens.Spacing.lg * 2
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DesignTokens.Spacing.lg)
    }
}

struct StreamingCapsuleInformationPanel: View {
    let information: StreamingPlaybackInformation

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(information.title)
                .font(DesignTokens.Typography.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Group {
                Text(information.leadingLabel)
                Text(information.trailingLabel)
            }
            .font(DesignTokens.Typography.metadata.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DesignTokens.Spacing.lg)
        .padding(.trailing, DesignTokens.Interactive.large)
        .accessibilityElement(children: .combine)
    }
}
