import DesignSystem
import PlaybackFeature
import PlaybackPresentation
import SwiftUI

enum PlaybackTopSecondaryMenu: String {
    case videoFormat
}

struct PlaybackVideoFormatSelection: Equatable {
    let projection: PlaybackModel.ProjectionType
    let stereoLayout: PlaybackModel.StereoLayout
}

enum PlaybackVideoFormatEditingDecision {
    case cancel
    case apply
}

struct PlaybackTopActionsState {
    var presentedMenu: PlaybackTopSecondaryMenu?
    var selectedEffect: SpatialSceneDomain.EnvironmentEffect
    var projection: PlaybackModel.ProjectionType
    var stereoLayout: PlaybackModel.StereoLayout

    private var selectionBeforeEditing: PlaybackVideoFormatSelection

    init(
        presentedMenu: PlaybackTopSecondaryMenu? = nil,
        selectedEffect: SpatialSceneDomain.EnvironmentEffect = .day,
        projection: PlaybackModel.ProjectionType = .equirectangular180,
        stereoLayout: PlaybackModel.StereoLayout = .mono
    ) {
        self.presentedMenu = presentedMenu
        self.selectedEffect = selectedEffect
        self.projection = projection
        self.stereoLayout = stereoLayout
        self.selectionBeforeEditing = PlaybackVideoFormatSelection(
            projection: projection,
            stereoLayout: stereoLayout
        )
    }

    mutating func toggleMenu(_ menu: PlaybackTopSecondaryMenu) {
        if presentedMenu == menu {
            dismissMenu()
            return
        }

        if presentedMenu == .videoFormat {
            discardVideoFormatChanges()
        }
        if menu == .videoFormat {
            selectionBeforeEditing = currentVideoFormatSelection
        }
        presentedMenu = menu
    }

    mutating func dismissMenu() {
        if presentedMenu == .videoFormat {
            discardVideoFormatChanges()
        }
        presentedMenu = nil
    }

    mutating func finishVideoFormatEditing(
        _ decision: PlaybackVideoFormatEditingDecision
    ) -> PlaybackVideoFormatSelection? {
        guard presentedMenu == .videoFormat else { return nil }
        presentedMenu = nil
        switch decision {
        case .cancel:
            discardVideoFormatChanges()
            return nil
        case .apply:
            let selection = currentVideoFormatSelection
            selectionBeforeEditing = selection
            return selection
        }
    }

    mutating func selectDockEffect(
        _ effect: SpatialSceneDomain.EnvironmentEffect
    ) -> SpatialSceneDomain.EnvironmentEffect {
        selectedEffect = effect
        return effect
    }

    private var currentVideoFormatSelection: PlaybackVideoFormatSelection {
        PlaybackVideoFormatSelection(
            projection: projection,
            stereoLayout: stereoLayout
        )
    }

    private mutating func discardVideoFormatChanges() {
        projection = selectionBeforeEditing.projection
        stereoLayout = selectionBeforeEditing.stereoLayout
    }
}

struct PlaybackTopActions: View {
    private let canDock: Bool
    private let canApplyFormat: Bool
    private let canUseFisheye: Bool
    private let resumesPanorama: Bool
    private let onDock: ((SpatialSceneDomain.EnvironmentEffect) -> Void)?
    private let onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)?
    private let onResumePanorama: (() -> Void)?
    private let onSecondaryMenuVisibilityChange: ((Bool) -> Void)?

    @State private var state: PlaybackTopActionsState

    init(
        initialPresentedMenu: PlaybackTopSecondaryMenu? = nil,
        canDock: Bool = true,
        canApplyFormat: Bool = true,
        canUseFisheye: Bool = false,
        resumesPanorama: Bool = false,
        onDock: ((SpatialSceneDomain.EnvironmentEffect) -> Void)? = nil,
        onApplyFormat: ((PlaybackModel.ProjectionType, PlaybackModel.StereoLayout) -> Void)? = nil,
        onResumePanorama: (() -> Void)? = nil,
        onSecondaryMenuVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.canDock = canDock
        self.canApplyFormat = canApplyFormat
        self.canUseFisheye = canUseFisheye
        self.resumesPanorama = resumesPanorama
        self.onDock = onDock
        self.onApplyFormat = onApplyFormat
        self.onResumePanorama = onResumePanorama
        self.onSecondaryMenuVisibilityChange = onSecondaryMenuVisibilityChange
        _state = State(
            initialValue: PlaybackTopActionsState(
                presentedMenu: initialPresentedMenu == .videoFormat
                    ? .videoFormat
                    : nil
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            WindowPlaybackSpatialActions {
                if canDock {
                    dockSystemMenu
                }
            } formatControl: {
                if resumesPanorama {
                    GlassCircleIconButton.expandVertically(
                        accessibilityLabel: "Return to Panorama",
                        action: { onResumePanorama?() },
                        accessibilityIdentifier: "PlayerUI-TopAction-resumePanorama"
                    )
                } else {
                    GlassCircleIconButton.expandVertically(
                        accessibilityLabel: "Video Format",
                        action: { toggle(.videoFormat) },
                        accessibilityIdentifier: "PlayerUI-TopAction-videoFormat"
                    )
                    .disabled(!canApplyFormat)
                }
            }

            if state.presentedMenu == .videoFormat {
                videoFormatMenu
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .zIndex(10)
            }
        }
        .onAppear {
            onSecondaryMenuVisibilityChange?(state.presentedMenu != nil)
        }
        .onDisappear {
            onSecondaryMenuVisibilityChange?(false)
        }
        .onChange(of: canApplyFormat) { _, available in
            if available == false, state.presentedMenu == .videoFormat { dismissMenu() }
        }
    }

    private var environmentDisplayName: String {
        SpatialSceneDomain.CinemaEnvironment.enchron.displayName
    }

    private var dockSystemMenu: some View {
        GlassCircleIconMenu(
            systemName: "mountain.2.fill",
            accessibilityLabel: "Dock",
            accessibilityIdentifier: "PlayerUI-TopAction-dock",
            iconTier: .compact
        ) {
            Section {
                dockMenuItem(effect: .day)
                dockMenuItem(effect: .night)
            } header: {
                Text("在 \(environmentDisplayName) 中观看")
            }
            .onAppear {
                if state.presentedMenu == .videoFormat {
                    dismissMenu()
                }
            }
        }
    }

    private func dockMenuItem(
        effect: SpatialSceneDomain.EnvironmentEffect
    ) -> some View {
        Button {
            let requested = state.selectDockEffect(effect)
            onDock?(requested)
        } label: {
            Label {
                Text(environmentDisplayName)
            } icon: {
                dockAppearanceIcon(for: effect)
            }
        }
        .accessibilityLabel("\(environmentDisplayName), \(effect.displayName)")
        .accessibilityIdentifier("PlayerUI-DockMenu-\(effect.rawValue)")
        .accessibilityAddTraits(
            state.selectedEffect == effect ? .isSelected : []
        )
    }

    private func dockAppearanceIcon(
        for effect: SpatialSceneDomain.EnvironmentEffect
    ) -> some View {
        let isLight = effect == .day
        return ZStack {
            Circle()
                .fill(.white)
                .opacity(isLight ? 1 : 0)

            AppearanceModeGlyph(isActive: isLight)
                .frame(
                    width: DesignTokens.ButtonIcon.standardArtwork,
                    height: DesignTokens.ButtonIcon.standardArtwork
                )
                .rotationEffect(.degrees(isLight ? 180 : 0))
        }
        .frame(
            width: DesignTokens.Interactive.regular,
            height: DesignTokens.Interactive.regular
        )
    }

    private func toggle(_ menu: PlaybackTopSecondaryMenu) {
        state.toggleMenu(menu)
        onSecondaryMenuVisibilityChange?(state.presentedMenu != nil)
    }

    private func dismissMenu() {
        state.dismissMenu()
        onSecondaryMenuVisibilityChange?(false)
    }

    private func cancelVideoFormat() {
        _ = state.finishVideoFormatEditing(.cancel)
        onSecondaryMenuVisibilityChange?(false)
    }

    private func applyVideoFormat() {
        guard let selection = state.finishVideoFormatEditing(.apply) else { return }
        onSecondaryMenuVisibilityChange?(false)
        onApplyFormat?(selection.projection, selection.stereoLayout)
    }

    private var videoFormatMenu: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            menuHeading("Video Format", supporting: "Choose how the video is presented")

            formatPicker(
                title: "Projection",
                selection: $state.projection,
                options: [
                    PlaybackModel.ProjectionType.equirectangular180,
                    .equirectangular360
                ] + (canUseFisheye ? [.fisheye] : []),
                label: projectionTitle
            )

            formatPicker(
                title: "Stereo Layout",
                selection: $state.stereoLayout,
                options: PlaybackModel.StereoLayout.allCases,
                label: stereoTitle
            )

            HStack {
                Spacer()
                Button("Cancel") {
                    cancelVideoFormat()
                }
                .accessibilityIdentifier("PlayerUI-VideoFormat-cancel")
                Button("Apply") {
                    applyVideoFormat()
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
