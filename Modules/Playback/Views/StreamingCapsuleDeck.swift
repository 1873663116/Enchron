import DesignSystem
import SwiftUI

struct StreamingCapsuleDeck: View {
    let information: StreamingPlaybackInformation?
    var onInteraction: () -> Void = {}

    var body: some View {
        StreamingCapsule(
            panelSize: panelSize,
            accessibilityIdentifierPrefix: "PlayerUI-StreamingCapsule",
            leading: { _ in settingsSlot },
            center: { _ in dockSlot },
            trailing: { expansion in informationSlot(expansion) },
            panel: { informationPanel }
        )
    }

    private var settingsSlot: some View {
        StreamingCapsuleSlotButton(
            accessibilityLabel: String(localized: "Settings"),
            accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-settings",
            action: {},
            icon: { ButtonSymbol(systemName: "gear") }
        )
        .disabled(true)
    }

    private var dockSlot: some View {
        PlaybackDockMenuTrigger { isMenuPresented in
            StreamingCapsuleSlotButton(
                accessibilityLabel: String(localized: "Dock"),
                accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-dock",
                action: {
                    onInteraction()
                    isMenuPresented.wrappedValue.toggle()
                },
                icon: { ButtonSymbol(systemName: "mountain.2.fill") }
            )
        }
    }

    private func informationSlot(_ expansion: Binding<Bool>) -> some View {
        StreamingCapsuleSlotButton(
            accessibilityLabel: String(localized: "Streaming Information"),
            accessibilityIdentifier: "PlayerUI-StreamingCapsule-button-information",
            action: {
                onInteraction()
                expansion.wrappedValue = true
            },
            icon: { ButtonSymbol(systemName: "info.circle") }
        )
        .disabled(information == nil)
    }

    @ViewBuilder
    private var informationPanel: some View {
        if let information {
            StreamingCapsuleInformationPanel(information: information)
        }
    }

    private var panelSize: CGSize {
        CGSize(
            width: DesignTokens.ControlBar.contentWidth,
            height: DesignTokens.Layout.playbackMediaInfoHeight * 2
        )
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
