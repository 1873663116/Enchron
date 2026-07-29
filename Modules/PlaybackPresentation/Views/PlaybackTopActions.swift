import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

enum PlaybackTopSecondaryMenu: String {
    case dock
    case videoFormat
}

struct PlaybackTopActions: View {
    private let canDock: Bool
    private let canApplyFormat: Bool
    private let canUseFisheye: Bool
    private let resumesPanorama: Bool
    private let onDock: ((SpatialSceneDomain.EnvironmentEffect) -> Void)?
    private let onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)?
    private let onResumePanorama: (() -> Void)?

    @State private var presentedMenu: PlaybackTopSecondaryMenu?
    @State private var selectedEffect: SpatialSceneDomain.EnvironmentEffect = .day
    @State private var projection: PlaybackModel.ProjectionType = .equirectangular180
    @State private var stereoLayout: PlaybackModel.StereoLayout = .mono

    init(
        initialPresentedMenu: PlaybackTopSecondaryMenu? = nil,
        canDock: Bool = true,
        canApplyFormat: Bool = true,
        canUseFisheye: Bool = false,
        resumesPanorama: Bool = false,
        onDock: ((SpatialSceneDomain.EnvironmentEffect) -> Void)? = nil,
        onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)? = nil,
        onResumePanorama: (() -> Void)? = nil
    ) {
        self.canDock = canDock
        self.canApplyFormat = canApplyFormat
        self.canUseFisheye = canUseFisheye
        self.resumesPanorama = resumesPanorama
        self.onDock = onDock
        self.onApplyFormat = onApplyFormat
        self.onResumePanorama = onResumePanorama
        _presentedMenu = State(initialValue: initialPresentedMenu)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if canDock {
                topActionButton(
                    title: "Dock",
                    systemName: "square.stack.3d.up",
                    menu: .dock,
                    isEnabled: true
                )
            }

            if resumesPanorama {
                Button(action: { onResumePanorama?() }) {
                    ButtonIconLabel(
                        title: "Return to Panorama",
                        systemName: "pano"
                    )
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .frame(minHeight: DesignTokens.Interactive.regular)
                }
                .buttonStyle(.plain)
                .clipShape(Capsule())
                .enchronGlassBackground(in: Capsule())
                .accessibilityIdentifier("PlayerUI-TopAction-resumePanorama")
            } else {
                topActionButton(
                    title: "Panorama",
                    systemName: "pano",
                    menu: .videoFormat,
                    isEnabled: canApplyFormat
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            Group {
                switch presentedMenu {
                case .dock: dockMenu
                case .videoFormat: videoFormatMenu
                case nil: EmptyView()
                }
            }
            .offset(y: DesignTokens.Interactive.large)
            .zIndex(10)
        }
        .onChange(of: canDock) { _, available in
            if available == false, presentedMenu == .dock { presentedMenu = nil }
        }
        .onChange(of: canApplyFormat) { _, available in
            if available == false, presentedMenu == .videoFormat { presentedMenu = nil }
        }
    }

    private func topActionButton(
        title: String,
        systemName: String,
        menu: PlaybackTopSecondaryMenu,
        isEnabled: Bool
    ) -> some View {
        Button {
            presentedMenu = presentedMenu == menu ? nil : menu
        } label: {
            ButtonIconLabel(title: title, systemName: systemName)
                .foregroundStyle(isEnabled ? .white : .secondary)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(minHeight: DesignTokens.Interactive.regular)
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .enchronGlassBackground(in: Capsule())
        .enchronHoverContentShape(Capsule())
        .enchronHoverEffect(.automatic)
        .frame(minHeight: DesignTokens.Interactive.large)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityIdentifier("PlayerUI-TopAction-\(menu.rawValue)")
    }

    private var dockMenu: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            menuHeading("Dock", supporting: "Use the active environment, or Enchron Environment by default")

            VStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(SpatialSceneDomain.EnvironmentEffect.allCases, id: \.self) { effect in
                    Button {
                        selectedEffect = effect
                        presentedMenu = nil
                        onDock?(effect)
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            ButtonSymbol(
                                systemName: effect == .day ? "sun.max" : "moon.stars",
                                tier: .label
                            )
                                .frame(width: DesignTokens.Interactive.regular)

                            Text(effect.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if selectedEffect == effect {
                                ButtonSymbol(systemName: "checkmark", tier: .label)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(DesignTokens.Typography.metadata)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .frame(minHeight: DesignTokens.Interactive.large)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .enchronHoverEffect(.highlight)
                    .accessibilityIdentifier("PlayerUI-DockMenu-\(effect.rawValue)")
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .enchronGlassBackground(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    private var videoFormatMenu: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            menuHeading("Video Format", supporting: "Choose how the video is presented")

            formatPicker(
                title: "Projection",
                selection: $projection,
                options: [
                    PlaybackModel.ProjectionType.equirectangular180,
                    .equirectangular360
                ] + (canUseFisheye ? [.fisheye] : []),
                label: projectionTitle
            )

            formatPicker(
                title: "Stereo Layout",
                selection: $stereoLayout,
                options: PlaybackModel.StereoLayout.allCases,
                label: stereoTitle
            )

            HStack {
                Spacer()
                Button("Cancel") {
                    presentedMenu = nil
                }
                .accessibilityIdentifier("PlayerUI-VideoFormat-cancel")
                Button("Apply") {
                    presentedMenu = nil
                    onApplyFormat?(projection, stereoLayout)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("PlayerUI-VideoFormat-apply")
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
        .enchronGlassBackground(in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous))
    }

    private func menuHeading(_ title: String, supporting: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(title)
                .font(DesignTokens.Typography.headline)
            Text(supporting)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func formatPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(DesignTokens.Typography.metadata)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option))
                        .tag(option)
                        .accessibilityIdentifier("PlayerUI-VideoFormat-\(title)-\(label(option))")
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    private func projectionTitle(_ projection: PlaybackModel.ProjectionType) -> String {
        switch projection {
        case .flat: "Flat"
        case .equirectangular180: "180°"
        case .equirectangular360: "360°"
        case .fisheye: "Fisheye"
        }
    }

    private func stereoTitle(_ stereoLayout: PlaybackModel.StereoLayout) -> String {
        switch stereoLayout {
        case .mono: "Mono"
        case .sideBySide: "Side-by-Side"
        case .topBottom: "Top-Bottom"
        }
    }
}
